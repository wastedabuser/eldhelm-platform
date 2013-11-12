package Eldhelm::Server::Main;

use strict;
use warnings;
use threads;
use threads::shared;
use Thread::Suspend;
use Socket;
use POSIX;
use IO::Handle;
use IO::Select;
use IO::Socket::SSL qw(debug3);
use IO::Socket::INET;
use Eldhelm::Util::MachineInfo;
use Eldhelm::Server::Worker;
use Eldhelm::Server::Logger;
use Eldhelm::Server::Executor;
use Data::Dumper;
use Time::HiRes qw(time usleep);
use Storable;
use Eldhelm::Util::Tool;
use Eldhelm::Util::Factory;
use Errno;

use base qw(Eldhelm::Server::AbstractChild);

my $currentFh;

$| = 1;

sub new {
	my ($class, %args) = @_;
	my $instance = $class->instance;
	if (!defined $instance) {
		$instance = {
			%args,
			info                 => { version => "1.3.0" },
			ioSocketList         => [],
			config               => shared_clone({}),
			workers              => [],
			workerQueue          => {},
			workerStatus         => {},
			connId               => 1,
			conidToFnoMap        => {},
			fnoToConidMap        => {},
			inputStreamMap       => {},
			outputStreamMap      => {},
			parseBufferMap       => {},
			connectionHandles    => {},
			connections          => shared_clone({}),
			connectionEvents     => shared_clone({}),
			delayedEvents        => shared_clone({}),
			responseQueue        => shared_clone({}),
			closeQueue           => shared_clone({}),
			persists             => shared_clone({}),
			persistsByType       => shared_clone({}),
			persistLookup        => shared_clone({}),
			workerStats          => {},
			connectionWorkerMap  => {},
			connectionWorkerLoad => {},
			jobQueue             => shared_clone([]),
			stash                => shared_clone({}),
			sslClients           => {},
			debugStreamMap       => {},
			fileContentCache     => {},
			proxySocketMap       => {},
			proxySocketS2SConn   => {},
		};
		bless $instance, $class;

		$instance->addInstance;

	}
	return $instance;
}

sub start {
	my ($self) = @_;

	$self->readConfig;
	$self->configure;
	$self->createLogger;
	$self->loadState;
	$self->init;
	$self->listen;

	return $self;
}

sub readConfig {
	my ($self) = @_;
	my $cfgPath = $self->{configPath} || "config.pl";
	die "No configuration file!" unless -f $cfgPath;

	print "Reading configuration from: $cfgPath\n";
	my $cfg = do $cfgPath;
	die "Can not read configuration: $@" if $@;

	lock($self->{config});
	%{ $self->{config} } = (%{ $self->{config} }, %{ shared_clone($cfg) });

	return $self;
}

sub configure {
	my ($self) = @_;

	$self->{debugMode} = $self->getConfig("debugMode");

	my $protoList = $self->{protoList} = $self->getConfig("server.acceptProtocols") || [];
	Eldhelm::Util::Factory->usePackage("Eldhelm::Server::Handler::$_") foreach @$protoList;

	return $self;
}

sub loadState {
	my ($self) = @_;

	my $cfg  = $self->getConfig("server");
	my $path = "$cfg->{tmp}/$cfg->{name}-state.res";

	return if !-f $path;

	$self->log("Loading $path from disk");
	my $data = Storable::retrieve($path);

	eval { $self->{$_} = shared_clone($data->{$_}) foreach keys %$data; };
	$self->error("State corrupt") if $@;
	unlink $path;

	return;
}

sub init {
	my ($self) = @_;

	my $cnf = $self->getConfig("server");
	my ($host, $port) = ($cnf->{host}, $cnf->{port});
	my @listen;
	@listen = map {
		{   host => $_->{host} || $cnf->{host},
			port => $_->{port} || $cnf->{port},
			ssl  => $_->{ssl}  || $cnf->{ssl}
		}
		} @{ $cnf->{listen} }
		if ref $cnf->{listen};

	foreach ($cnf, @listen) {
		my ($h, $p) = ($_->{host}, $_->{port});
		next if !$h || !$p;

		$h = Eldhelm::Util::MachineInfo->ip($h) if $h =~ /auto/;

		my $sockObj;
		if ($_->{ssl}) {
			$sockObj = IO::Socket::SSL->new(
				LocalHost    => $h,
				LocalPort    => $p,
				Proto        => 'tcp',
				Listen       => SOMAXCONN,
				Type         => SOCK_STREAM,
				Reuse        => 1,
				Blocking     => 0,
				SSL_server   => 1,
				SSL_use_cert => 1,
				%{ $_->{ssl} },
			) or die "IO::Socket: $!";
			$self->log("Listening $h:$p ssl");
		} else {
			$sockObj = IO::Socket::INET->new(
				LocalHost => $h,
				LocalPort => $p,
				Proto     => 'tcp',
				Listen    => SOMAXCONN,
				Type      => SOCK_STREAM,
				Reuse     => 1,
				Blocking  => 0,
			) or die "IO::Socket: $!";
			$self->log("Listening $h:$p");
		}

		$self->configConnection($sockObj);
		push @{ $self->{ioSocketList} }, $sockObj;
	}

	$self->{ioSelect} = IO::Select->new(@{ $self->{ioSocketList} }) || die "IO::Select $!\n";

	$self->{proxyConfig} = $self->getConfig("proxy");

	# start the executor
	$self->createExecutor;

	# start workers
	$self->{suspendWorkers} = $cnf->{suspendWorkers};
	foreach (1 .. $cnf->{workerCount} || 1) {
		$self->createWorker;
	}

	$SIG{PIPE} = sub {
		my $sig = shift @_;
		if ($currentFh) {
			my $fno = $currentFh->fileno;
			$self->error("A pipe $fno is broken");
			$self->removeConnection($currentFh, "pipe");
			$currentFh = undef;
		}
	};

	$SIG{INT} = sub {
		my $sig = shift @_;
		print "Server shutting down by INT signal\n";
		$self->saveStateAndShutDown;
	};

	$SIG{TERM} = sub {
		my $sig = shift @_;
		print "Server shutting down by TERM signal\n";
		$self->saveStateAndShutDown;
	};

	$SIG{HUP} = sub {
		my $sig = shift @_;
		print "Server re-reading configuration after HUP signal ...\n";
		$self->readConfig;
		print "Done\n";
	};
}

sub createLogger {
	my ($self) = @_;
	$self->{logQueue} = shared_clone({ map { +$_ => [] } keys %{ $self->getConfig("server.logger.logs") } });
	$self->{logger} =
		threads->create(\&Eldhelm::Server::Logger::create, map { +$_ => $self->{$_} } qw(config info logQueue));
	$self->{logger}->detach();
	return;
}

sub createExecutor {
	my ($self) = @_;
	my $executorQueue = shared_clone([]);
	my $workerStatus = shared_clone({ action => "startup" });
	my $t = $self->{executor} = threads->create(
		\&Eldhelm::Server::Executor::create,
		workerStatus => $workerStatus,
		workerQueue  => $executorQueue,
		map { +$_ => $self->{$_} }
			qw(config info logQueue connections responseQueue closeQueue persists persistsByType persistLookup delayedEvents connectionEvents jobQueue stash)
	);
	$self->log("Created executor: ".$t->tid);
	$self->{workerQueue}{ $t->tid }  = $executorQueue;
	$self->{workerStatus}{ $t->tid } = $workerStatus;
	$t->detach();
	return;
}

sub createWorker {
	my ($self, $jobs) = @_;
	my $workerQueue = shared_clone($jobs || []);
	my $workerStatus = shared_clone({ action => "startup" });
	my $t = threads->create(
		\&Eldhelm::Server::Worker::create,
		workerStatus => $workerStatus,
		workerQueue  => $workerQueue,
		map { +$_ => $self->{$_} }
			qw(config info logQueue connections responseQueue closeQueue persists persistsByType persistLookup delayedEvents jobQueue stash)
	);
	$self->log("Created worker: ".$t->tid);
	$self->{workerQueue}{ $t->tid }          = $workerQueue;
	$self->{workerStatus}{ $t->tid }         = $workerStatus;
	$self->{workerStats}{ $t->tid }{jobs}    = 0;
	$self->{connectionWorkerLoad}{ $t->tid } = 0;
	$t->detach();
	push @{ $self->{workers} }, $t;
	return;
}

sub listen {
	my ($self) = @_;

	my ($socketList, $select, $config, $sslClients, $acceptFlag, $hasPending, @clients) =
		($self->{ioSocketList}, $self->{ioSelect}, $self->getConfig("server"), $self->{sslClients});
	$self->log("Eldhelm server ready and listening ...");

	my $waitRest = $self->getConfig("waitOnRead") || .001;
	my $waitActive = $waitRest / 10;

	while (1) {

		$self->message("will read from socket");

		@clients = $select->can_read($hasPending ? $waitActive : $waitRest);
		$self->message("will iterate over sockets ".scalar @clients);

		push @clients, values %$sslClients;
		my %acceptedClients;

		foreach my $fh (@clients) {
			next if $acceptedClients{$fh};
			next unless ref $fh;

			$acceptFlag = 0;
			foreach my $socket (@$socketList) {
				next unless $fh == $socket;

				$acceptFlag = 1;
				my $conn = $self->acceptSock($socket, $fh);
				last unless $conn;

				$self->configConnection($conn);
				$self->createConnection($conn);
				$self->createProxyConnection($conn) if $self->{proxyConfig};

				last;
			}

			$acceptedClients{$fh} = 1;
			next if $acceptFlag;
			$currentFh = $fh;

			my $data = $self->readFromSock($fh);

			unless (defined($data) && length $data) {
				$self->removeConnection($fh, "remote");
			} else {
				$self->monitorConnection($fh, \$data);
				$self->addToStream($fh, $data);
			}
		}
		$self->message("will write to sockets");

		$hasPending = 0;
		@clients    = $select->can_write(0);
		$self->message("can write to socket ".scalar @clients);
		my $h = 0;
		foreach my $fh (@clients) {
			$self->message("write to $h");
			my $fno   = $fh->fileno;
			my $id    = $self->{fnoToConidMap}{$fno};
			my $queue = $self->{responseQueue}{$id};
			my $invalid;

			$self->message("lock $h");
			{
				lock($queue);
				$self->message("sending $h");
				if (@$queue) {
					if ($fh->connected) {
						$self->message("do send $h");
						while (my $ch = shift @$queue) {
							if (ref $ch && $ch->{file}) {
								$self->{outputStreamMap}{$fh} .= ${ $self->getFileContent($ch) };
								next;
							}
							$self->{outputStreamMap}{$fh} .= $ch;
						}
					} else {
						$self->error("A connection error occured while sending to $id($fno)");
						$invalid = 1;
					}
				}
			}
			$self->message("writen to $h");

			if ($invalid) {
				$self->message("remove $h");
				$self->removeConnection($fh, "unknown");
				$self->message("removed $h");
			} else {
				my $rr = \$self->{outputStreamMap}{$fh};
				if ($$rr) {
					$hasPending = 1 if $self->sendToSock($fh, $rr);
				}
			}

			$h++;
		}
		$self->message("writen to socket");

		{
			lock($self->{closeQueue});
			@clients = keys %{ $self->{closeQueue} };
		}
		$self->message("will close socket ".scalar @clients);
		$h = 0;
		foreach my $id (@clients) {
			my $fno = $self->{conidToFnoMap}{$id};
			unless ($fno) {
				lock($self->{closeQueue});
				delete $self->{closeQueue}{$id};
				next;
			}
			my $fh    = $self->{connectionHandles}{$fno};
			my $queue = $self->{responseQueue}{$id};
			my $ln;
			{
				lock($queue);
				$ln = @$queue;
			}
			$self->message("check close $h");
			if ($fh && !$ln && !$self->{outputStreamMap}{$fh}) {
				$self->message("close remove $h");
				$self->removeConnection($fh, "server");
				$self->message("close removed $h");
			}
			$h++;
		}
		$self->message("closed sockets");

		$self->message("will do other jobs");
		$self->doOtherJobs();
		$self->message("done other jobs");
	}

	$self->error("Server is going down");

}

sub acceptSock {
	my ($self, $socket, $fh) = @_;
	$self->message("accept $socket");
	my $conn;
	if (ref($socket) =~ /SSL/) {
		eval {
			local $SIG{ALRM} = sub {
				die "accept blocked";
			};
			alarm 3;
			$conn = $socket->accept();
			alarm 0;
		};
		$self->error("An alarm was fired while accepting $socket:\n$@") if $@;

		if ($conn || $@ || $!{ETIMEDOUT}) {
			delete $self->{sslClients}{$fh};
		} elsif (!$conn) {
			$self->{sslClients}{$fh} = $fh;
		}

	} else {
		$conn = $socket->accept();
	}
	return $conn;
}

sub readFromSock {
	my ($self, $fh) = @_;
	$self->message("read from $fh");
	my $data = "";
	eval {
		local $SIG{ALRM} = sub {
			die "read blocked";
		};
		alarm 3;
		if (ref($fh) =~ /SSL/) {
			$fh->sysread($data, 2048);
		} else {
			$fh->recv($data, POSIX::BUFSIZ, 0);    # 65536
		}
		alarm 0;
	};
	if ($@) {
		$self->error("An alarm was fired while reading over $fh:\n$@");
		return;
	}
	return $data;
}

sub sendToSock {
	my ($self, $fh, $data) = @_;
	if (ref $data ne "SCALAR") {
		$self->error("Data should be a scalar ref");
		$data = "";
		return \$data;
	}

	$currentFh = $fh;
	my $fileno = $fh->fileno;
	my $id     = $self->{fnoToConidMap}{$fileno};
	my ($charCnt, $block);
	eval {
		local $SIG{ALRM} = sub {
			die "send blocked: ".length($$data);
		};
		alarm 3;
		if (ref($fh) =~ /SSL/) {
			$charCnt = syswrite($fh, $$data, 0);
		} else {
			$charCnt = $fh->send($$data, 0);
		}
		$block = 1 if $!{EWOULDBLOCK};
		alarm 0;
	};
	if ($@) {
		$self->error("An alarm was fired while sending over $id($fileno):\n$@");
		$self->removeConnection($fh, "alarm");
		return $data;
	}
	if (!defined $charCnt) {
		$self->error("Can not write to $id($fileno)");
	} elsif ($block) {
		$self->error("Block; Buffer full for $id($fileno)");
		use bytes;
		substr($$data, 0, $charCnt) = "";
	} elsif ($charCnt < length $$data) {
		use bytes;
		substr($$data, 0, $charCnt) = "";
	} else {
		$$data = "";
	}

	return $data;
}

sub createConnection {
	my ($self, $sock, $out) = @_;
	$self->message("create connection $sock");

	$self->{ioSelect}->add($sock);
	my $fileno = $sock->fileno;

	my $cHandles = $self->{connectionHandles};
	my $oldSock  = $cHandles->{$fileno};
	$self->removeConnection($oldSock) if $oldSock;

	my $id = $self->{connId}++;
	$self->{fnoToConidMap}{$fileno}  = $id;
	$self->{inputStreamMap}{$fileno} = "";
	$cHandles->{$fileno}             = $sock;
	$self->{conidToFnoMap}{$id}      = $fileno;
	$self->{outputStreamMap}{$sock}  = "";

	{
		lock($self->{connections});
		$self->{connections}{$id} = shared_clone(
			{   fno              => $id,
				fileno           => $fileno,
				peeraddr         => $sock->peeraddr,
				peerport         => $sock->peerport,
				peerhost         => $sock->peerhost,
				sockaddr         => $sock->sockaddr,
				sockport         => $sock->sockport,
				sockhost         => $sock->sockhost,
				recvLength       => 0,
				connected        => 1,
				connectedOn      => time,
				lastActivityTime => time,
				avgPingSamples   => [],
			}
		);
	}

	$self->message("create connection response queue");
	{
		lock($self->{responseQueue});
		$self->{responseQueue}{$id} = shared_clone([]);
	}

	$self->log("Connection $id($fileno) ".($out ? "to" : "from")." ".$sock->peerhost." open", "access");
}

sub createProxyConnection {
	my ($self, $sock) = @_;

	my $pSock = $self->{proxySocketMap}{$sock} = IO::Socket::INET->new(
		PeerAddr => $self->{proxyConfig}{host},
		PeerPort => $self->{proxyConfig}{port} || $sock->sockport,
		Blocking => 0,
	);
	return unless $pSock;

	$self->{proxySocketS2SConn}{$pSock} = 1;
	$self->{proxySocketMap}{$pSock}     = $sock;

	$self->createConnection($pSock, 1);
	$self->configConnection($pSock);
}

sub configConnection {
	my ($self, $sock) = @_;
	$self->message("config $sock");

	$sock->autoflush(1);

	if (!Eldhelm::Util::MachineInfo->isWin) {
		use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
		my $flags = $sock->fcntl(F_GETFL, 0) or warn "Can't get flags for the socket: $!";
		$sock->fcntl(F_SETFL, $flags | O_NONBLOCK) or warn "Can't set flags for the socket: $!";
	} else {
		IO::Handle::blocking($sock, 0);
	}
}

sub monitorConnection {
	my ($self, $sock, $data) = @_;
	$self->message("monitor $sock");

	my $fileno = $sock->fileno;
	my $id     = $self->{fnoToConidMap}{$fileno};
	my $conn;
	{
		lock($self->{connections});
		$conn = $self->{connections}{$id};
	}

	lock($conn);

	$conn->{recvLength} += length $$data;
	$conn->{lastActivityTime} = time;

	return;
}

sub removeConnection {
	my ($self, $sock, $initiator) = @_;
	$self->message("remove connection $sock, $initiator");

	my $fileno = $sock->fileno;
	my $id     = $self->{fnoToConidMap}{$fileno};
	return unless $id;

	my ($event, $conn);
	{
		lock($self->{connections});
		$conn = delete $self->{connections}{$id};
	}

	if ($conn) {
		lock($conn);
		$conn->{connected} = 0;
	}

	{
		lock($self->{responseQueue});
		delete $self->{responseQueue}{$id};
	}

	{
		my $closeQueue = $self->{closeQueue};
		lock($closeQueue);
		$event = delete $closeQueue->{$id};

		# if there this is a proxy to another socket close it when possible
		my $pSock = $self->{proxySocketMap}{$sock};
		if ($pSock) {
			delete $self->{proxySocketMap}{$pSock};
			my $pId = $self->{fnoToConidMap}{ $pSock->fileno };
			$closeQueue->{$pId} = shared_clone(
				{   initiator => "server",
					reason    => "proxy",
				}
			) if $pId;
		}
	}
	delete $self->{conidToFnoMap}{$id};

	my $t = delete $self->{connectionWorkerMap}{$id};
	$self->{connectionWorkerLoad}{ $t->tid }-- if $t;

	delete $self->{fnoToConidMap}{$fileno};
	delete $self->{inputStreamMap}{$fileno};
	delete $self->{parseBufferMap}{$fileno};
	delete $self->{connectionHandles}{$fileno};

	if (!$sock) {
		$self->error("Connection $id($fileno) is not available any more");
		return;
	}

	delete $self->{proxySocketMap}{$sock};
	delete $self->{proxySocketS2SConn}{$sock};
	delete $self->{outputStreamMap}{$sock};
	$self->{ioSelect}->remove($sock);
	$self->log("Connection $id($fileno) from ".$sock->peerhost." closed by $initiator", "access");

	$sock->close;

	if (is_shared($event)) {
		my $eventsClone;
		{
			lock($event);
			$eventsClone = Eldhelm::Util::Tool::cloneStructure($event);
		}
		$self->registerConnectionEvent("disconnect", $eventsClone, $id);
		return;
	}

	$self->registerConnectionEvent(
		"disconnect",
		{   reason    => "close",
			initiator => $initiator,
		},
		$id
	);

}

sub addToStream {
	my ($self, $sock, $data) = @_;

	if ($self->{proxyConfig} && $self->{proxySocketS2SConn}{$sock}) {
		$self->addToProxyStream($sock, $data);
		return;
	}

	$self->message("adding chunk to stream ".length($data));
	my $fileno = $sock->fileno;
	$self->{debugStreamMap}{$fileno} = $self->{inputStreamMap}{$fileno} .= $data;

	while ($self->readSocketData($sock)) { }
}

sub addToProxyStream {
	my ($self, $sock, $data) = @_;
	my $pSock = $self->{proxySocketMap}{$sock};
	return unless $pSock;

	$self->send($pSock, $data);
}

sub readSocketData {
	my ($self, $sock) = @_;
	my $fileno = $sock->fileno;
	my $stream = \$self->{inputStreamMap}{$fileno};
	return unless $$stream;

	my $buff = $self->{parseBufferMap}{$fileno} ||= { len => 0 };
	my ($flag, $exec);

	my ($proto, $parser) = ($buff->{proto}, $buff->{parser});
	unless ($proto) {
		$proto  = $buff->{proto}  = $self->detectProto($$stream);
		$parser = $buff->{parser} = "Eldhelm::Server::Handler::$proto";
	}

	if ($proto && !$buff->{content}) {
		my $hParsed;
		eval { ($hParsed, $$stream) = $parser->parse($$stream, $self); };
		if ($@) {
			$self->error("Error parsing chunk '$$stream': $@");
			return;
		}
		%$buff = (%$hParsed, proto => $proto, parser => $parser);
		$self->executeBufferedTask($sock, $buff) if $buff->{len} == -1 || $buff->{len} == 0;
		return 1 if $buff->{len} != -2;

	} elsif ($buff->{len} > 0) {
		$exec = 0;
		{
			use bytes;
			my $ln = length $$stream;
			if ($ln > $buff->{len}) {
				my $dln = $buff->{len};
				my $chunk = substr $$stream, 0, $dln;
				substr($$stream, 0, $dln) = "";
				$buff->{content} .= $chunk;
				$buff->{len} = 0;
				$exec        = 1;
				$flag        = 1;

			} elsif ($ln == $buff->{len}) {
				$buff->{content} .= $$stream;
				$$stream     = "";
				$buff->{len} = 0;
				$exec        = 1;

			} else {
				$buff->{content} .= $$stream;
				$$stream = "";
				$buff->{len} -= $ln;

			}
		}
		$self->executeBufferedTask($sock, $buff) if $exec;
		return 1 if $flag;

	} elsif (length $$stream >= 20) {
		$self->error("Unsupported protocol for message: ".$$stream." => $self->{debugStreamMap}{$fileno}");
		$$stream = "";
	}

	return;
}

sub detectProto {
	my ($self, $data) = @_;
	my $protoList = $self->{protoList};
	foreach (@$protoList) {
		my $pkg = "Eldhelm::Server::Handler::$_";
		return $_ if $pkg->check($data);
	}
	return;
}

sub executeBufferedTask {
	my ($self, $sock, $buff) = @_;

	$self->message("execute bufered task");
	delete $self->{parseBufferMap}{ $sock->fileno };

	if ($self->{proxyConfig} && !$buff->{parser}->proxyPossible($buff)) {
		$self->addToProxyStream($sock, $buff->{data});
		return;
	}

	$self->executeTask($sock, $buff);
	return;
}

sub executeTask {
	my ($self, $sock, $data) = @_;

	my $fno = $sock->fileno;
	my $id  = $self->{fnoToConidMap}{$fno};

	if ($data->{proto} eq "System") {
		$self->handleTransmissionFlags($sock, $id, $data);
		return;
	}

	$self->delegateToWorker($id, $data);
	return;
}

sub handleTransmissionFlags {
	my ($self, $sock, $id, $data) = @_;
	my $cmd = $data->{command};
	return if !$cmd;

	$self->message("handle flags");
	if ($cmd eq "ping") {
		my $conn;
		{
			lock($self->{connections});
			$conn = $self->{connections}{$id};
		}

		lock($conn);
		$conn->{keepalive}   = 1;
		$conn->{timeSample2} = time;

		return;
	}
	if ($cmd eq "echo") {
		$self->send($sock, "-echo-");
		return;
	}
}

sub delegateToWorker {
	my ($self, $id, $data) = @_;
	return if $self->{shuttingDown};

	my $t   = $self->selectWorker($id);
	my $tid = $t->tid;
	$self->log("Delegating to worker $tid: [proto:$data->{proto}; len:".($data->{len} || "")."]");

	{
		my $queue = $self->{workerQueue}{$tid};
		lock($queue);

		push @$queue, shared_clone([ $id, $data ]);
	}
	$self->{workerStats}{$tid}{jobs}++;

	$t->resume if $self->{suspendWorkers};

	$self->message("delegated worker");
	return;
}

sub selectWorker {
	my ($self, $id) = @_;

	$self->message("select worker");
	my ($chosen, @list);
	$chosen = $self->{connectionWorkerMap}{$id} if $id;

	foreach my $t (@{ $self->{workers} }) {
		my $isSusp = $t->is_suspended;
		my $tid    = $t->tid;
		my %stats  = (
			tid      => $tid,
			sleeping => $isSusp ? 1 : 2,
			status   => $isSusp ? "_" : "W",
			queue    => scalar @{ $self->{workerQueue}{$tid} },
			conn     => $self->{connectionWorkerLoad}{$tid},
			trd      => $t
		);
		$stats{weight} = ($stats{queue} + $stats{conn}) * $stats{sleeping};
		push @list, \%stats;

	}
	$self->log(
		"Worker load: ["
			.join(", ",
			map { "$_->{tid}:$_->{status}q$_->{queue}c$_->{conn}\($self->{workerStats}{$_->{tid}}{jobs}\)" } @list)
			."]"
	);
	$chosen = [ sort { $a->{weight} <=> $b->{weight} } @list ]->[0]{trd}
		if !$chosen;

	if ($id && !$self->{connectionWorkerMap}{$id}) {
		$self->{connectionWorkerMap}{$id} = $chosen;
		$self->{connectionWorkerLoad}{ $chosen->tid }++;
	}

	return $chosen;
}

sub send {
	my ($self, $sock, $msg) = @_;
	$self->{outputStreamMap}{$sock} .= $msg;
	return $self;
}

sub registerConnectionEvent {
	my ($self, $type, $options, $connId) = @_;

	my $evs = $self->{connectionEvents};
	lock($evs);

	my $ce = $evs->{$connId};
	if (!$ce) {
		$evs->{$connId} = shared_clone({ $type => $options });
	} else {
		lock($ce);
		$ce->{$type} = shared_clone($options);
	}
}

sub doOtherJobs {
	my ($self) = @_;
	my $job;
	{
		my $queue = $self->{jobQueue};
		lock($queue);

		return if !@$queue;
		$job = shift @$queue;
	}

	if ($job->{job} eq "gracefullRestart") {
		$self->gracefullRestart;
		return;
	}

	if ($job->{job} eq "evaluateCodeMain") {
		$self->evaluateCodeMain($job);
		return;
	}

	$self->delegateToWorker(undef, $job);
	return;
}

sub evaluateCodeMain {
	my ($self, $job) = @_;
	return unless $job->{code};

	eval $job->{code};
	$self->error("Error while evaluating code in main context: $@") if $@;
}

# =================================
# Restarting and shutting down
# =================================

sub removeWorker {
	my ($self, $t) = @_;
	my $tid = $t->tid;
	$self->log("Removing worker: $tid");

	my @jobs;
	{
		my $queue = $self->{workerQueue}{$tid};
		lock($queue);
		@jobs   = @$queue;
		@$queue = ("exitWorker");
	}

	$t->resume if $t->is_suspended;

	delete $self->{workerQueue}{$tid};
	delete $self->{workerStatus}{$tid};
	delete $self->{workerStats}{$tid};
	return \@jobs;
}

sub removeExecutor {
	my ($self) = @_;

	my $tid = $self->{executor}->tid;
	$self->log("Removing executor: $tid");

	{
		my $queue = $self->{workerQueue}{$tid};
		lock($queue);

		@$queue = ("exitWorker");
	}

	delete $self->{workerQueue}{$tid};
	delete $self->{workerStatus}{$tid};
	return;
}

sub gracefullRestart {
	my ($self) = @_;
	$self->readConfig;

	$self->removeExecutor;
	$self->createExecutor;

	my @workers = @{ $self->{workers} };
	@{ $self->{workers} } = ();
	foreach (@workers) {
		$self->createWorker($self->removeWorker($_));
	}

	%{ $self->{connectionWorkerMap} } = ();
	return;
}

sub saveStateAndShutDown {
	my ($self) = @_;

	return if $self->{shuttingDown};

	$self->{shuttingDown} = 1;
	print "Saving state ...\n";

	# TODO: find a way to save waiting jobs for every worker something with the waiting jobs
	# the problem is that they are per connection and when connections are lost these jobs are meaningless
	my %statuses = %{ $self->{workerStatus} };

	$self->removeExecutor;
	$self->removeWorker($_) foreach @{ $self->{workers} };

	# wait for all workers to stop
	my $wait;
	do {
		print "Waiting for workers...\n" if $wait;
		usleep(250_000);
		$wait = 0;
		foreach my $st (values %statuses) {
			lock $st;
			$wait = 1 if $st->{action} ne "exit";
		}
	} while ($wait);

	# just to be sure!
	usleep(100_000);

	# get the persist data
	my @persistsList;
	{
		my $persists = $self->{persists};
		lock($persists);

		@persistsList = values %$persists;
	}

	foreach (@persistsList) {
		next unless $_;

		my $obj = $self->getPersistFromRef($_);
		next unless $obj;

		$obj->beforeSaveState;
	}

	my $data = Eldhelm::Util::Tool::cloneStructure(
		{ map { +$_ => $self->{$_} } qw(stash persists persistsByType persistLookup delayedEvents jobQueue) });

	my $cfg  = $self->getConfig("server");
	my $path = "$cfg->{tmp}/$cfg->{name}-state.res";
	print "Writing $path to disk\n";
	Storable::store($data, $path);

	print "Bye bye\n";
	exit;
}

# =================================
# Utility
# =================================

sub DESTROY {
	my ($self) = @_;
	$self->log("Termination successful");
}

sub message {
	my ($self, $msg) = @_;
	return unless $self->{debugMode};

	my $path = $self->{messagesLogPath} ||=
		$self->getConfig("server.logger.path")."/".($self->getConfig("server.logger.messageLog") || "messages.log");
	unlink $path if $self->{debugMessageCount} > 0 && !($self->{debugMessageCount} % 100_000);
	$self->{debugMessageCount}++;

	open FW, ">>$path";
	print FW time." $msg\n";
	close FW;

	return;
}

sub getFileContent {
	my ($self, $args) = @_;
	use bytes;

	my $cache = $self->{fileContentCache};
	my ($path, $ln) = ($args->{file}, $args->{ln});

	my $content;
	$content = \$cache->{$path} if $cache->{$path};

	if (!$content || $ln != length $$content) {
		my $buf;
		eval {
			$self->log("Open '$path'", "access");
			open FILE, $path or confess $!;
			binmode FILE;
			my $data;
			while (read(FILE, $data, 4) != 0) {
				$buf .= $data;
			}
			close FILE or confess $!;
			$self->log("File '$path' is ".length($buf), "access");
		};
		$self->error("Error reading file: $@") if $@;
		$cache->{$path} = $buf;
		return \$cache->{$path};

	} else {
		$self->log("From cache '$path'", "access");
	}

	return $content;
}

1;
