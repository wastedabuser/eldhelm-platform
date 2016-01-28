package Eldhelm::Server::Main;

use strict;
use warnings;

use threads;
use threads::shared;
use Socket;
use POSIX;
use IO::Handle;
use IO::Select;

# use IO::Socket::SSL qw(debug3);
use IO::Socket::SSL;
use IO::Socket::INET;
use Data::Dumper;
use Time::HiRes qw(time usleep);
use Errno;
use Eldhelm::Util::MachineInfo;
use Eldhelm::Server::Worker;
use Eldhelm::Server::Logger;
use Eldhelm::Server::Executor;
use Eldhelm::Util::Tool;
use Eldhelm::Util::Factory;

use base qw(Eldhelm::Server::AbstractChild);

my $currentFh;

$| = 1;

sub new {
	my ($class, %args) = @_;
	my $instance = $class->instance;
	if (!defined $instance) {
		$instance = {
			%args,
			info => { version => "1.4.5" },
			config => shared_clone($args{config} || {}),

			endMainLoopCounter   => -1,
			ioSocketList         => [],
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
			responseQueue        => {},
			closeMap             => {},
			workerStats          => {},
			connectionWorkerMap  => {},
			connectionWorkerLoad => {},
			sslClients           => {},
			debugStreamMap       => {},
			fileContentCache     => {},
			proxySocketMap       => {},
			proxySocketS2SConn   => {},
			reservedWorkerId     => {},
			debugMessageCount    => 0,
			lastHeartbeat        => time,
			jobQueue             => [],

			hpsList => {},
			hps     => {},

			persists       => shared_clone({}),
			persistsByType => shared_clone({}),
			persistLookup  => shared_clone({}),
			stash          => shared_clone({}),
			delayedEvents  => shared_clone({}),

			connections      => shared_clone({}),
			connectionEvents => shared_clone({}),
			sheduledEvents   => shared_clone({}),

			serverStats => shared_clone({}),

			workerCountU => 1,
			workerCountR => 2,
			workerCount  => 5
		};
		bless $instance, $class;

		$instance->addInstance;

	}
	return $instance;
}

### UNIT TEST: 000_message_parsing.pl ###

sub start {
	my ($self) = @_;

	$self->readConfig;
	$self->configure;
	$self->loadState;

	$self->createLogger;
	$self->init;

	my $startHanlers = $self->getConfig("server.handlers.start");
	if ($startHanlers && @$startHanlers) {
		$self->doAction(@$_) foreach @$startHanlers;
	}

	$self->listen;

	return $self;
}

sub readConfig {
	my ($self) = @_;
	my $cfgPath = $self->{configPath} ||= "config.pl";
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

	$self->{debugMode}         = $self->getConfig("debugMode");
	$self->{heartbeatInterval} = $self->getConfig("server.monitoring.heartbeat.interval");

	my $protoList = $self->{protoList} = $self->getConfig("server.acceptProtocols") || [];
	Eldhelm::Util::Factory->usePackage("Eldhelm::Server::Handler::$_") foreach @$protoList;

	return $self;
}

sub loadState {
	my ($self) = @_;

	my $cfg = $self->getConfig("server");
	my $path;
	$path = "$cfg->{tmp}/$cfg->{name}-state.res" if $cfg->{tmp} && $cfg->{name};

	return if !$path || !-f $path;

	# stash persists persistsByType persistLookup delayedEvents jobQueue
	print "Reading state from: $path\n";
	eval {
		my $data = do $path;
		if ($data) {
			print "State is loading ...\n";
			foreach my $k (keys %$data) {
				my $d = $data->{$k};
				print "Loading $k: ";
				if (ref $d eq "HASH") {
					print scalar(keys %$d)." items";
					foreach (keys %$d) {
						$self->{$k}{$_} = shared_clone($d->{$_});
						usleep(10_000);
					}
				} elsif (ref $d eq "ARRAY") {
					print scalar(@$d)." items";
					$self->{$k} = shared_clone($d);
				}
				print "\n";
			}
		} else {
			print "State is empty!\n";
		}
	};
	if ($@) {
		print "State corrupt: $@\n";
	} else {
		print "State loaded\n";
	}
	rename $path, $path."-".int(time).".res";

	return;
}

sub clearCache {
	my ($self) = @_;
	%{ $self->{fileContentCache} } = ();
	$self->{messagesLogPath} = "";
}

sub init {
	my ($self) = @_;

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
		print "Received INT signal\n";

		$self->callSaveStateHandler;
	};

	$SIG{TERM} = sub {
		my $sig = shift @_;
		print "Received TERM signal\n";

		$self->callSaveStateHandler;
	};

	$SIG{HUP} = sub {
		my $sig = shift @_;
		print "Received HUP signal\n";

		print "Server clearing cache and re-reading configuration ...\n";
		$self->clearCache;
		$self->readConfig;
		$self->configure;
		$self->reconfigAllWorkers;
		$self->reconfigExecutor;
		$self->reconfigLogger;
		print "Done\n";
	};

	my $cnf = $self->getConfig("server");
	my @listen;
	@listen = map {
		{   host => $_->{host} || $cnf->{host},
			port => $_->{port} || $cnf->{port},
			ssl  => $_->{ssl}  || $cnf->{ssl}
		}
		} @{ $cnf->{listen} }
		if ref $cnf->{listen};

	my @autoList;
	foreach ($cnf, @listen) {
		my ($h, $p, $s) = ($_->{host}, $_->{port}, $_->{ssl});
		next unless $h =~ /auto/;
		push @autoList, map { { host => $_, port => $p, ssl => $s } } Eldhelm::Util::MachineInfo->ip($h);
	}

	foreach ($cnf, @listen, @autoList) {
		my ($h, $p) = ($_->{host}, $_->{port});
		next if !$h || !$p || $h =~ /auto/;

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
	$self->{workerCountU} = $cnf->{workerCountU} if $cnf->{workerCountU};
	$self->{workerCountR} = $cnf->{workerCountR} if $cnf->{workerCountR};
	$self->{workerCount}  = $cnf->{workerCount}  if $cnf->{workerCount};
	foreach (1 .. $self->{workerCount}) {
		$self->createWorker;
	}

}

sub createLogger {
	my ($self) = @_;
	my $workerStatus = shared_clone({ action => "startup" });
	$self->{logQueue} = shared_clone(
		{   threadCmdQueue => [],
			map { +$_ => [] } keys %{ $self->getConfig("server.logger.logs") }
		}
	);
	my $t = $self->{logger} = threads->create(
		\&Eldhelm::Server::Logger::create,
		workerStatus => $workerStatus,
		map { +$_ => $self->{$_} } qw(config info logQueue)
	);
	$self->{workerStatus}{ $t->tid } = $workerStatus;
	$t->detach();
	return;
}

sub createExecutor {
	my ($self) = @_;
	my $executorQueue = shared_clone([]);
	my $workerStatus  = shared_clone({ action => "startup" });
	my $responseQueue = shared_clone([]);
	my $t             = $self->{executor} = threads->create(
		\&Eldhelm::Server::Executor::create,
		workerStatus  => $workerStatus,
		workerQueue   => $executorQueue,
		responseQueue => $responseQueue,
		map { +$_ => $self->{$_} }
			qw(config info logQueue connections persists persistsByType persistLookup delayedEvents sheduledEvents connectionEvents stash)
	);
	$self->log("Created executor: ".$t->tid);
	$self->{workerQueue}{ $t->tid }   = $executorQueue;
	$self->{workerStatus}{ $t->tid }  = $workerStatus;
	$self->{responseQueue}{ $t->tid } = $responseQueue;
	$t->detach();
	return;
}

sub createWorker {
	my ($self, $jobs) = @_;
	my $workerQueue = shared_clone($jobs || []);
	my $workerStatus = shared_clone({ action => "startup" });
	my $responseQueue = shared_clone([]);

	my $type;
	my $reservedCount = scalar keys %{ $self->{reservedWorkerId} };
	if ($reservedCount < $self->{workerCountU}) {
		$type = "U";
	} elsif ($reservedCount < $self->{workerCountU} + $self->{workerCountR}) {
		$type = "R";
	} else {
		$type = "";
	}

	my $t = threads->create(
		\&Eldhelm::Server::Worker::create,
		workerType    => $type,
		workerStatus  => $workerStatus,
		workerQueue   => $workerQueue,
		responseQueue => $responseQueue,
		map { +$_ => $self->{$_} }
			qw(configPath config info logQueue connections persists persistsByType persistLookup sheduledEvents serverStats stash)
	);
	$self->log("Created worker: ".$t->tid);
	$self->{workerQueue}{ $t->tid }  = $workerQueue;
	$self->{workerStatus}{ $t->tid } = $workerStatus;
	$self->{workerStats}{ $t->tid } ||= {};
	$self->{workerStats}{ $t->tid }{jobs} = 0;
	$self->{responseQueue}{ $t->tid } = $responseQueue;

	$self->{workerStats}{ $t->tid }{type} = $type;
	$self->{reservedWorkerId}{ $t->tid } = 1 if $type;

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

	my $waitRest = $self->getConfig("waitOnRead") || .01;
	my $waitActive = $waitRest / 10;

	while (1) {
		last unless $self->{endMainLoopCounter};
		$self->{endMainLoopCounter}-- if $self->{endMainLoopCounter} > 0;

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
				$self->addToStream($fh, \$data);
			}
		}

		$self->message("gathering responses");
		my (%responseQueues, @delays, @delaysCancels);
		my @tids = keys %{ $self->{responseQueue} };
		foreach my $tid (@tids) {
			my $tq = $self->{responseQueue}{$tid};
			next unless $tq;

			lock($tq);
			while (@$tq) {
				my ($id, $d) = (shift @$tq, shift @$tq);
				if (ref $d) {
					if ($d->{proto}) {
						push @{ $self->{jobQueue} }, $d;
					} elsif ($d->{stamp}) {
						push @delays, $d;
					} elsif (defined $d->{cancelDelayId}) {
						push @delaysCancels, $d->{cancelDelayId};
					} elsif (!$d->{file}) {
						$self->{closeMap}{$id} = $d;
					} else {
						push @{ $responseQueues{$id} }, $d;
					}
				} else {
					push @{ $responseQueues{$id} }, $d;
				}
			}
		}

		$self->registerDelayEvent($_) foreach @delays;
		$self->cancelDelayEvent($_)   foreach @delaysCancels;

		@clients = keys %responseQueues;
		$self->message("responses for clients: ".scalar @clients);
		foreach my $id (@clients) {
			my $fno = $self->{conidToFnoMap}{$id};
			next unless $fno;

			my $invalid;
			my $fh    = $self->{connectionHandles}{$fno};
			my $queue = $responseQueues{$id};
			if ($queue) {
				if ($fh->connected) {
					$self->message("do send $id");
					while (my $ch = shift @$queue) {
						if (ref $ch) {
							lock($ch);
							if ($ch->{file}) {
								$self->send($fh, $self->getFileContent($ch));
								next;
							}
						}
						$self->send($fh, $ch);
					}
				} else {
					$self->error("A connection error occured while sending to $id($fno)");
					$invalid = 1;
				}
			}

			if ($invalid) {
				$self->message("remove $id");
				$self->removeConnection($fh, "unknown");
				$self->message("removed $id");
			}
		}

		$hasPending = 0;
		@clients    = keys %{ $self->{outputStreamMap} };
		$self->message("responding to clients: ".scalar @clients);
		foreach my $fno (@clients) {
			my $fh = $self->{connectionHandles}{$fno};
			next if !$fh || !$fh->connected;

			my $rr = \$self->{outputStreamMap}{$fno};
			if ($$rr) {
				$hasPending = 1 if $self->sendToSock($fh, $rr);
			}
		}

		@clients = keys %{ $self->{closeMap} };
		$self->message("will close socket ".scalar @clients);
		foreach my $id (@clients) {
			my $fno = $self->{conidToFnoMap}{$id};
			next unless $fno;

			my $fh = $self->{connectionHandles}{$fno};
			$self->message("check close $id");
			if ($fh && !$self->{outputStreamMap}{$fno}) {
				$self->message("close remove $id");
				$self->removeConnection($fh, "server");
				$self->message("close removed $id");
			}
		}

		$self->message("do heartbeat");
		$self->heartbeat();

		$self->message("will do other jobs");
		$self->doOtherJobs();

		$self->captureStats;
	}

	print "Main loop ended with status $self->{endMainLoopReason}\n";
	if ($self->{endMainLoopReason} eq "saveState") {
		$self->saveStateAndShutDown;
	}

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
		return $data;
	}
	my $ssl = ref($fh) =~ /SSL/;
	if (!$fh->peeraddr) {
		$self->error("No peer address");
		$self->removeConnection($fh, "no peeraddr");
		return $data;
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
		if ($ssl) {
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

		# some error but this case seems to be normal
		# $self->error("Can not write to $id($fileno)");
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
	$self->removeConnection($oldSock, "replace") if $oldSock;

	my $id = $self->{connId}++;
	$self->{fnoToConidMap}{$fileno}   = $id;
	$self->{inputStreamMap}{$fileno}  = "";
	$cHandles->{$fileno}              = $sock;
	$self->{conidToFnoMap}{$id}       = $fileno;
	$self->{outputStreamMap}{$fileno} = "";

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

	$self->log(
		"Connection $id($fileno) "
			.($out ? "to" : "from")." '"
			.($sock->peerhost || "host unknown").":"
			.($sock->peerport || "port unknown")
			."' via '"
			.($sock->sockhost || "host unknown").":"
			.($sock->sockport || "port unknown")
			."' open",
		"access"
	);
}

sub createProxyConnection {
	my ($self, $sock) = @_;

	my $port  = $sock->sockport;
	my $pconf = $self->{proxyConfig};
	my $pmap  = $pconf->{portmap};
	my $pSock = $self->{proxySocketMap}{$sock} = IO::Socket::INET->new(
		PeerAddr => $pconf->{host},
		PeerPort => $pconf->{port} || ($pmap ? $pmap->{$port} || $port : $port),
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

	my $event = delete $self->{closeMap}{$id};

	my $conn;
	{
		lock($self->{connections});
		$conn = delete $self->{connections}{$id};
	}

	if ($conn) {
		lock($conn);
		$conn->{connected} = 0;
	}

	# if there this is a proxy to another socket close it when possible
	my $pSock = $self->{proxySocketMap}{$sock};
	if ($pSock) {
		delete $self->{proxySocketMap}{$pSock};
		my $pId = $self->{fnoToConidMap}{ $pSock->fileno };
		$self->{closeMap}{$pId} = shared_clone(
			{   initiator => "server",
				reason    => "proxy",
			}
		) if $pId;
	}

	delete $self->{conidToFnoMap}{$id};

	my $t = delete $self->{connectionWorkerMap}{$id};
	$self->{connectionWorkerLoad}{ $t->tid }-- if $t;

	delete $self->{fnoToConidMap}{$fileno};
	delete $self->{inputStreamMap}{$fileno};
	delete $self->{parseBufferMap}{$fileno};
	delete $self->{connectionHandles}{$fileno};
	delete $self->{outputStreamMap}{$fileno};

	delete $self->{proxySocketMap}{$sock};
	delete $self->{proxySocketS2SConn}{$sock};

	$self->{ioSelect}->remove($sock);
	$self->log(
		"Connection $id($fileno) from '"
			.($sock->peerhost || "host unknown").":"
			.($sock->peerport || "port unknown")
			."' via '"
			.($sock->sockhost || "host unknown").":"
			.($sock->sockport || "port unknown")
			."' closed by $initiator",
		"access"
	);

	$sock->close;

	if (is_shared($event)) {
		my $eventsClone;
		{
			lock($event);
			$eventsClone = Eldhelm::Util::Tool->cloneStructure($event);
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

	$self->message("adding chunk to stream ".length($$data));
	my $fileno = $sock->fileno;
	$self->{debugStreamMap}{$fileno} = $self->{inputStreamMap}{$fileno} .= $$data;
	$self->log($data, "receive");

	while ($self->readSocketData($sock)) { }
}

sub addToProxyStream {
	my ($self, $sock, @data) = @_;
	my $pSock = $self->{proxySocketMap}{$sock};
	return unless $pSock;

	$self->send($pSock, $_) foreach grep { $$_ } @data;
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
		$proto = $buff->{proto} = $self->detectProto($$stream);
		$parser = $buff->{parser} = "Eldhelm::Server::Handler::$proto" if $proto;
	}

	if ($proto && !$buff->{content} && (!$buff->{len} || $buff->{len} < 0)) {
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
		my $ln;
		{
			use bytes;
			$ln = length $$stream;
		}
		if ($ln > $buff->{len}) {
			my $dln = $buff->{len};
			my $chunk;
			{
				use bytes;
				$chunk = substr $$stream, 0, $dln;
				substr($$stream, 0, $dln) = "";
			}
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

	$self->countHit($buff->{proto});

	if ($self->{proxyConfig} && $buff->{parser}->proxyPossible($buff, $self->{proxyConfig}{proxyUrls})) {
		$self->addToProxyStream($sock, \$buff->{headerContent}, \$buff->{content});
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

	my $t = $self->selectWorker($id, $data->{priority});
	return unless $t;

	my $tid = $t->tid;
	$self->log("Delegating to worker $tid: [proto:$data->{proto}; len:".($data->{len} || "")."]");

	{
		my $queue = $self->{workerQueue}{$tid};
		lock($queue);

		push @$queue, shared_clone([ $id, $data ]);
	}
	$self->{workerStats}{$tid}{jobs}++;

	$self->message("delegated worker");
	return;
}

# priority - 0 high, 1 low
sub selectWorker {
	my ($self, $id, $priority) = @_;

	$self->message("select worker");
	return unless @{ $self->{workers} };

	my @list;
SLLP: foreach my $t (@{ $self->{workers} }) {
		my $tid = $t->tid;
		my ($pendingJob, $status, $queueLn);
		{
			my $tStatus = $self->{workerStatus}{$tid};
			next SLLP unless $tStatus;

			lock $tStatus;
			$status     = $tStatus->{action};
			$pendingJob = "$tStatus->{proto};$tStatus->{task}";
		}
		{
			my $tQueue = $self->{workerQueue}{$tid};
			next SLLP unless $tQueue;

			lock $tQueue;
			$queueLn = scalar @$tQueue;
		}
		my %stats = (
			tid     => $tid,
			status  => $status,
			queue   => $queueLn,
			pending => $pendingJob,
			conn    => $self->{connectionWorkerLoad}{$tid},
			type    => $self->{workerStats}{$tid}{type},
			trd     => $t
		);
		$stats{weight} = $stats{queue} + $stats{conn};
		push @list, \%stats;

	}
	return unless @list;

	$self->{workerStatusMessage} = join(
		", ",
		map {
			"$_->{tid}$_->{type}:$_->{status}q$_->{queue}c$_->{conn}\($self->{workerStats}{$_->{tid}}{jobs};$_->{pending}\)"
		} @list
	);
	$self->log("Worker load: [$self->{workerStatusMessage}]");

	my @chooseList = @list;
	my $chosen;
	if ($priority) {
		@chooseList = grep { $_->{type} eq "U" } @chooseList;
	} elsif ($id) {
		$chosen = $self->{connectionWorkerMap}{$id};
		unless ($chosen) {
			@chooseList = grep { !$_->{type} } @chooseList;
		}
	} else {
		my @highPriority = grep { $_->{type} ne "U" } @chooseList;
		@chooseList = @highPriority if @highPriority;
	}

	@chooseList = @list unless @chooseList;
	$chosen = [ sort { $a->{weight} <=> $b->{weight} } @chooseList ]->[0]{trd}
		unless $chosen;

	if ($id && !$self->{connectionWorkerMap}{$id}) {
		$self->{connectionWorkerMap}{$id} = $chosen;
		$self->{connectionWorkerLoad}{ $chosen->tid }++;
	}

	return $chosen;
}

sub send {
	my ($self, $sock, $msg) = @_;
	$self->{outputStreamMap}{ $sock->fileno } .= ref $msg ? $$msg : $msg;
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

sub registerDelayEvent {
	my ($self, $delay) = @_;
	my $stamp;
	{
		lock($delay);
		$stamp = $delay->{stamp};
	}

	my $devs = $self->{delayedEvents};
	lock($devs);

	my $list = $devs->{$stamp};
	$list = $devs->{$stamp} = shared_clone([]) unless $list;
	push @$list, $delay;
}

sub cancelDelayEvent {
	my ($self, $delayId) = @_;

	my ($stamp, $num) = split /-/, $delayId;
	return if !$stamp || !defined $num;

	my @events;
	my $devs = $self->{delayedEvents};
	{
		lock($devs);

		my $list = $devs->{$stamp};
		return unless $list;
		@events = @$list;
	}

	foreach my $ev (@events) {
		lock($ev);
		next if $ev->{delayId} ne $delayId;
		$ev->{canceled} = 1;
	}
}

sub doOtherJobs {
	my ($self) = @_;
	return unless $self->otherJobCount;

	my $sharedJob = shift @{ $self->{jobQueue} };
	my $job;
	{
		lock($sharedJob);
		$job = Eldhelm::Util::Tool->cloneStructure($sharedJob);
	}

	if ($job->{job} eq "gracefullRestart") {
		$self->gracefullRestart;
		return;
	}

	if ($job->{job} eq "evaluateCodeMain") {
		$self->evaluateCodeMain($job);
		return;
	}

	$self->delegateToWorker($job->{connectionId}, $job);
	return;
}

sub otherJobCount {
	my ($self) = @_;
	return $self->{jobQueue} ? scalar @{ $self->{jobQueue} } : 0;
}

sub evaluateCodeMain {
	my ($self, $job) = @_;
	return unless $job->{code};

	eval $job->{code};
	$self->error("Error while evaluating code in main context: $@") if $@;
}

sub heartbeat {
	my ($self) = @_;
	return unless $self->{heartbeatInterval};
	return if $self->{lastHeartbeat} + $self->{heartbeatInterval} >= time;
	$self->{lastHeartbeat} = time;

	$self->doAction("monitoring.heartbeat:sendHeartbeat", { message => $self->{workerStatusMessage} });
}

sub countHit {
	my ($self, $proto) = @_;
	my $h = $self->{hps};
	$h->{All}++;
	$h->{$proto}++;
}

sub captureStats {
	my ($self) = @_;
	return if $self->{lastHps} + 1 >= time;
	$self->{lastHps} = time;

	my $stats;
	my $hpsV = $self->{hps};
	my $hpsL = $self->{hpsList};
	foreach my $p (keys %$hpsV) {
		my $hps = $hpsV->{$p};
		$hpsV->{$p} = 0;
		my $la = $hpsL->{$p} ||= [];
		push @$la, $hps;

		shift @$la if @$la > 5;
		my $sum = 0;
		$sum += $_ foreach @$la;
		my $avgHps = $sum / 10;

		$stats = $self->{serverStats};
		{
			lock($stats);
			$stats->{"currentHps$p"} = $hps;
			$stats->{"averageHps$p"} = $avgHps;
		}
	}

	$stats = $self->{serverStats};
	{
		lock($stats);
		$stats->{workerStatus} = $self->{workerStatusMessage};
	}
}

# =================================
# Reconfiguring
# =================================

sub reconfigAllWorkers {
	my ($self) = @_;
	foreach (@{ $self->{workers} }) {
		$self->reconfigWorker($_);
	}
}

sub reconfigWorker {
	my ($self, $t) = @_;
	my $tid = $t->tid;
	$self->log("Reconfiguring worker: $tid");

	my @jobs;
	{
		my $queue = $self->{workerQueue}{$tid};
		lock($queue);
		@jobs = @$queue;
		push @$queue, "reconfig";
	}
	return \@jobs;
}

sub reconfigExecutor {
	my ($self) = @_;

	my $tid = $self->{executor}->tid;
	$self->log("Reconfiguring executor: $tid");

	{
		my $queue = $self->{workerQueue}{$tid};
		lock($queue);

		push @$queue, "reconfig";
	}
	return;
}

sub reconfigLogger {
	my ($self) = @_;

	my $tid = $self->{logger}->tid;
	$self->log("Reconfiguring logger: $tid");

	{
		my $queue = $self->{logQueue}{threadCmdQueue};
		lock($queue);

		push @$queue, "reconfig";
	}
	return;
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
		@jobs = @$queue;
		push @$queue, "exitWorker";
	}

	delete $self->{workerQueue}{$tid};
	delete $self->{workerStatus}{$tid};
	delete $self->{workerStats}{$tid};
	delete $self->{responseQueue}{$tid};
	delete $self->{reservedWorkerId}{$tid};
	return \@jobs;
}

sub removeExecutor {
	my ($self) = @_;
	return unless $self->{executor};

	my $tid = $self->{executor}->tid;
	$self->log("Removing executor: $tid");

	{
		my $queue = $self->{workerQueue}{$tid};
		lock($queue);

		push @$queue, "exitWorker";
	}

	delete $self->{workerQueue}{$tid};
	delete $self->{workerStatus}{$tid};
	delete $self->{responseQueue}{$tid};
	return;
}

sub removeLogger {
	my ($self) = @_;
	return unless $self->{logger};

	my $tid = $self->{logger}->tid;
	$self->log("Removing logger: $tid");

	{
		my $queue = $self->{logQueue}{threadCmdQueue};
		lock($queue);

		push @$queue, "exitWorker";
	}

	delete $self->{workerStatus}{$tid};
	return;
}

sub gracefullRestart {
	my ($self) = @_;
	$self->readConfig;

	$self->removeExecutor;
	$self->createExecutor;

	%{ $self->{reservedWorkerId} } = ();
	my @workers = @{ $self->{workers} };
	@{ $self->{workers} } = ();
	foreach (@workers) {
		$self->createWorker($self->removeWorker($_));
	}

	%{ $self->{connectionWorkerMap} } = ();
	return;
}

sub callSaveStateHandler {
	my ($self) = @_;
	my $saveStateHanlers = $self->getConfig("server.handlers.saveState");
	if ($saveStateHanlers && @$saveStateHanlers) {
		foreach (@$saveStateHanlers) {
			print "Calling $_->[0] ...\n";
			$self->doAction(@$_);
		}
	}
	$self->{endMainLoopReason}  = "saveState";
	$self->{endMainLoopCounter} = 5;
}

sub saveStateAndShutDown {
	my ($self) = @_;

	print "Saving state ...\n";

	my $cfg = $self->getConfig("server");
	if (!$cfg->{name} || !$cfg->{tmp} || !-d $cfg->{tmp}) {
		print "Saving state is not available, bye bye\n";
		exit;
	}

	# TODO: find a way to save waiting jobs for every worker something with the waiting jobs
	# the problem is that they are per connection and when connections are lost these jobs are meaningless
	my %statuses = %{ $self->{workerStatus} };

	$self->removeExecutor;
	$self->removeWorker($_) foreach @{ $self->{workers} };
	@{ $self->{workers} } = ();
	$self->removeLogger;

	# wait for all workers to stop
	my $wait = 1;
	do {
		print "Waiting for $wait threads to go down ... \n" if $wait;
		usleep(250_000);
		$wait = 0;
		foreach my $st (values %statuses) {
			lock($st);
			next if $st->{action} eq "exit";
			print "Still running $st->{proto}:$st->{task}\n" if $st->{proto};
			$wait++;
		}
	} while ($wait);

	# just to be sure!
	usleep(100_000);

	# clear some memory
	$self->clearCache;

	# get the persist data
	my @persistsList;
	{
		my $persists = $self->{persists};
		lock($persists);

		@persistsList = values %$persists;
	}

	print "Calling beforeSaveState on ".scalar(@persistsList)." persist objects\n";
	foreach (@persistsList) {
		next unless $_;

		my $obj = $self->getPersistFromRef($_);
		next unless $obj;

		$obj->beforeSaveState;
	}

	my $data = {};
	foreach (qw(stash persists persistsByType persistLookup delayedEvents jobQueue)) {
		$data->{$_} = $self->{$_};
		delete $self->{$_};
	}

	my $path = "$cfg->{tmp}/$cfg->{name}-state.res";
	print "Writing $path to disk\n";
	$self->saveResFile($data, $path);

	print "Bye bye\n";
	exit;
}

sub saveResFile {
	my ($self, $data, $file) = @_;
	open my $fh, '>', $file
		or die "Can't write '$file': $!";
	local $Data::Dumper::Sparseseen = 1;    # no seen structure
	local $Data::Dumper::Terse      = 1;    # no '$VAR1 = '
	local $Data::Dumper::Useqq      = 1;    # double quoted strings
	local $Data::Dumper::Deepcopy   = 1;
	local $Data::Dumper::Maxdepth   = 10;
	print $fh Dumper $data;
	close $fh or die "Can't close '$file': $!";
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

=pod

=head1 NAME

Eldhelm::Server::Main - An application server called The Eldhelm Platform.

=head1 SYNOPSIS

	use strict;
	use Eldhelm::Server::Main;
	
	# with a config.pl
	Eldhelm::Server::Main->new->start;
	
	# you can try this for a quick start
	Eldhelm::Server::Main->new(
		configPath => 'quickstart-config.pl'
	)->start;
	
	# or with your custom configuration
	Eldhelm::Server::Main->new(
		configPath => 'myCustomConfig.pl'
	)->start;

=head1 DESCRIPTION

A flexible, production ready, application server which can do advanced stuff (WOW).

The server traps some signals:

=over

=item HUP

When you C<kill -HUP> the server, it reloads the configuration file.
Pelase note that the server will not recreate any threads or sockets.
For all changes to apply you need to restart the server!

=item INT

When you C<kill -INT> the server will gracefully shut down.
It will attempt to save it's state (if configured to do so).

=item TERM

Same as INT.

=item PIPE

Will nag about a broken pipe and attempt to continue normal operation.

=back

=head1 METHODS

=over

=item new(%args)

Constructs the server object.

C<%args> Hash - Contructor argumets;

C<configPath> - specifies a configuration file. Defaults to C<config.pl>;

=item start()

Starts the server.

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
