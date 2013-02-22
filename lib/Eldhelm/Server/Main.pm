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
use Eldhelm::Server::Worker;
use Eldhelm::Server::Logger;
use Eldhelm::Server::Executor;
use Data::Dumper;
use Time::HiRes qw(time usleep);
use Storable;
use Eldhelm::Util::Tool;
use Eldhelm::Util::Factory;

use base qw(Eldhelm::Server::AbstractChild);

my ($currentFh, $isWin);

$| = 1;

sub new {
	my ($class, %args) = @_;
	my $instance = $class->instance;
	if (!defined $instance) {
		$instance = {
			info                 => { version => "1.2.1" },
			ioSocketList         => [],
			config               => {},
			workers              => [],
			workerQueue          => {},
			connId               => 1,
			connidMap            => {},
			filenoMap            => {},
			streamMap            => {},
			buffMap              => {},
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
			slowSocket           => {},
		};
		bless $instance, $class;

		$instance->addInstance;

		$instance->readConfig;
		$instance->createLogger;
		$instance->loadState;
		$instance->init;
		$instance->listen;

	}
	return $instance;
}

sub readConfig {
	my ($self) = @_;
	if (-f "config.pl") {
		$self->{config} = do "config.pl";
		die "Can not read configuration: $@" if $@;
	} else {
		die "No configuration file!";
	}
	return $self;
}

sub loadState {
	my ($self) = @_;

	my $cfg  = $self->{config}{server};
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

	$isWin = 1 if $^O =~ m/mswin/i;

	my $protoList = $self->{config}{server}{acceptProtocols} ||= [];
	Eldhelm::Util::Factory->usePackage("Eldhelm::Server::Handler::$_") foreach @$protoList;

	my $cnf = $self->{config}{server};
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
		$self->error("Server shutting down by int command");
		$self->saveStateAndShutDown;
	};

	$SIG{TERM} = sub {
		my $sig = shift @_;
		$self->error("Server shutting down by term command");
		$self->saveStateAndShutDown;
	};

	$SIG{HUP} = sub {
		my $sig = shift @_;
		$self->error("Server restarting gracefully by hup command");
		$self->gracefullRestart;
	};
}

sub createLogger {
	my ($self) = @_;
	$self->{logQueue} = shared_clone({ map { +$_ => [] } keys %{ $self->{config}{server}{logger}{logs} } });
	$self->{logger} =
		threads->create(\&Eldhelm::Server::Logger::create, map { +$_ => $self->{$_} } qw(config info logQueue));
	$self->{logger}->detach();
	return;
}

sub createExecutor {
	my ($self) = @_;
	my $executorQueue = shared_clone([]);
	my $t = $self->{executor} = threads->create(
		\&Eldhelm::Server::Executor::create,
		workerQueue => $executorQueue,
		map { +$_ => $self->{$_} }
			qw(config info logQueue connections responseQueue closeQueue persists persistsByType persistLookup delayedEvents connectionEvents jobQueue stash)
	);
	$self->log("Created executor: ".$t->tid);
	$self->{workerQueue}{ $t->tid } = $executorQueue;
	$t->detach();
	return;
}

sub createWorker {
	my ($self, $jobs) = @_;
	my $workerQueue = shared_clone($jobs || []);
	my $t = threads->create(
		\&Eldhelm::Server::Worker::create,
		workerQueue => $workerQueue,
		map { +$_ => $self->{$_} }
			qw(config info logQueue connections responseQueue closeQueue persists persistsByType persistLookup delayedEvents jobQueue stash)
	);
	$self->log("Created worker: ".$t->tid);
	$self->{workerQueue}{ $t->tid }          = $workerQueue;
	$self->{workerStats}{ $t->tid }{jobs}    = 0;
	$self->{connectionWorkerLoad}{ $t->tid } = 0;
	$t->detach();
	push @{ $self->{workers} }, $t;
	return;
}

sub listen {
	my ($self) = @_;

	my ($socketList, $select, $config, $acceptFlag, $hasPending, @clients, %sslClients) =
		($self->{ioSocketList}, $self->{ioSelect}, $self->{config}{server});
	$self->log("Eldhelm server ready and listening ...");

	while (1) {

		$self->message("will read from socket");

		# @clients = $select->can_read($hasPending || $self->closingConnectionsCount || $self->hasJobs ? 0 : .004);
		@clients = $select->can_read($hasPending ? 0 : .0001);
		$self->message("will iterate over sockets ".scalar @clients);

		push @clients, values %sslClients;
		my %acceptedClients;

		foreach my $fh (@clients) {
			next if $acceptedClients{$fh};
			next unless ref $fh;

			$acceptFlag = 0;
			foreach my $socket (@$socketList) {
				next unless $fh == $socket;

				$acceptFlag = 1;
				my $conn = $self->acceptSock($socket);
				unless ($conn) {
					$sslClients{$fh} = $fh;
					last;
				}
				delete $sslClients{$fh};

				$self->configConnection($conn);
				$self->createConnection($conn);

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
			my $fileno = $fh->fileno;
			my $fno    = $self->{filenoMap}{$fileno};
			my $queue  = $self->{responseQueue}{$fno};
			my $invalid;

			$self->message("lock $h");
			{
				lock($queue);
				$self->message("sending $h");
				if (@$queue) {
					if ($fh->connected) {
						$self->message("do send $h");
						shift @$queue unless length ${ $self->sendToSock($fh, \$queue->[0]) };
					} else {
						$self->error("A connection error occured while sending to $fno($fileno)");
						$invalid = 1;
					}
				}
				$hasPending = 1 if @$queue;
			}
			$self->message("writen to $h");

			if ($invalid) {
				$self->message("remove $h");
				$self->removeConnection($fh, "unknown");
				$self->message("removed $h");
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
		foreach (@clients) {
			my $queue = $self->{responseQueue}{$_};
			next unless $queue;
			my $len;

			$self->message("lock close $h");
			{
				lock($queue);
				$len = @$queue;
			}
			$self->message("check close $h");
			if ($len < 1) {
				$self->message("close remove $h");
				$self->removeConnection($_, "server");
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
	my ($self, $socket) = @_;
	$self->message("accept $socket");
	my $conn;
	if ($isWin || ref($socket) !~ /SSL/) {
		$conn = $socket->accept();
	} else {
		my $ss = $self->{slowSocket};
		return if $ss->{$socket} && $ss->{$socket} + 5 > time;
		eval {
			local $SIG{ALRM} = sub {
				die "accept blocked";
			};
			Time::HiRes::ualarm(100_000);
			$conn = $socket->accept();
			Time::HiRes::ualarm(0);
		};
		if ($@) {
			$self->error("An alarm was fired while accepting $socket:\n$@");
			$ss->{$socket} = time;
			return;
		}
		delete $ss->{$socket} if $ss->{$socket} && $conn;
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
	my $id     = $self->{filenoMap}{$fileno};
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
		$block = 1 if $! == POSIX::EWOULDBLOCK;
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
		substr($$data, 0, $charCnt) = "";
	} elsif ($charCnt < length $$data) {
		substr($$data, 0, $charCnt) = "";
	} else {
		$$data = "";
	}

	return $data;
}

sub createConnection {
	my ($self, $sock) = @_;
	$self->message("create connection $sock");

	$self->{ioSelect}->add($sock);
	my $fileno = $sock->fileno;

	my $cHandles = $self->{connectionHandles};
	my $oldSock  = $cHandles->{$fileno};
	$self->removeConnection($oldSock) if $oldSock;

	my $id = $self->{connId}++;
	$self->{filenoMap}{$fileno} = $id;
	$self->{streamMap}{$fileno} = "";
	$cHandles->{$fileno}        = $sock;
	$self->{connidMap}{$id}     = $fileno;

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

	$self->log("Connection $id($fileno) from ".$sock->peerhost." open", "access");
}

sub configConnection {
	my ($self, $sock) = @_;
	$self->message("config $sock");

	$sock->autoflush(1);

	if (!$isWin) {
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
	my $id     = $self->{filenoMap}{$fileno};
	my $conn   = $self->{connections}{$id};
	lock($conn);

	$conn->{recvLength} += length $$data;
	$conn->{lastActivityTime} = time;

	return;
}

sub removeConnection {
	my ($self, $fh, $initiator) = @_;
	$self->message("remove connection $fh, $initiator");

	my ($id, $fileno, $sock);
	if (ref $fh) {
		$fileno = $fh->fileno;
		$id     = $self->{filenoMap}{$fileno};
		$sock   = $fh;
	} else {
		$fileno = $self->{connidMap}{$fh};
		$id     = $fh;
		$sock   = $self->{connectionHandles}{$fileno} if $fileno;
	}

	return if !$id;
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
		lock($self->{closeQueue});
		$event = delete $self->{closeQueue}{$id};
	}
	delete $self->{connidMap}{$id};
	my $t = delete $self->{connectionWorkerMap}{$id};
	$self->{connectionWorkerLoad}{ $t->tid }-- if $t;

	return if !$fileno;
	delete $self->{filenoMap}{$fileno};
	delete $self->{streamMap}{$fileno};
	delete $self->{buffMap}{$fileno};
	delete $self->{connectionHandles}{$fileno};

	if (!$sock) {
		$self->error("Connection $id($fileno) is not available any more");
		return;
	}

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
	$self->message("adding chunk to stream ".length($data));
	$self->{streamMap}{ $sock->fileno } .= $data;
	$self->readSocketData($sock);
}

sub readSocketData {
	my ($self, $sock) = @_;
	my $fileno = $sock->fileno;
	my $stream = \$self->{streamMap}{$fileno};
	my $buff   = $self->{buffMap}{$fileno} ||= { len => 0 };
	my $flag;

	my $proto = $self->detectProto($$stream);
	if ($proto && !$buff->{content}) {
		my $hParsed;
		my $parser = "Eldhelm::Server::Handler::$proto";
		eval { ($hParsed, $$stream) = $parser->parse($$stream, $self); };
		if ($@) {
			$self->error("Error parsing chunk '$$stream': $@");
			return;
		}
		%$buff = (%$hParsed, proto => $proto);
		$self->executeBufferedTask($sock, $buff) if $buff->{len} == -1 || $buff->{len} == 0;
		$flag = 1 if $buff->{len} != -2;

	} elsif ($buff->{len} > 0) {
		my $ln = length $$stream;
		if ($ln > $buff->{len}) {
			my $dln = $buff->{len};
			my $chunk = substr $$stream, 0, $dln;
			substr($$stream, 0, $dln) = "";
			$buff->{content} .= $chunk;
			$buff->{len} = 0;
			$self->executeBufferedTask($sock, $buff);
			$flag = 1;

		} elsif ($ln == $buff->{len}) {
			$buff->{content} .= $$stream;
			$$stream = "";
			$buff->{len} = 0;
			$self->executeBufferedTask($sock, $buff);

		} else {
			$buff->{content} .= $$stream;
			$$stream = "";
			$buff->{len} -= $ln;

		}
	} elsif (length $$stream >= 20) {
		$self->error("Unsupported protocol for message: ".$$stream);
		$$stream = "";
	}

	$self->readSocketData($sock) if $$stream && $flag;

	return;
}

sub detectProto {
	my ($self, $data) = @_;
	my $protoList = $self->{config}{server}{acceptProtocols};
	foreach (@$protoList) {
		my $pkg = "Eldhelm::Server::Handler::$_";
		return $_ if $pkg->check($data);
	}
	return;
}

sub executeBufferedTask {
	my ($self, $sock, $buff) = @_;
	$self->message("execute bufered task");
	delete $self->{buffMap}{ $sock->fileno };
	$self->executeTask($sock, $buff);
	return;
}

sub executeTask {
	my ($self, $sock, $data) = @_;

	my $fno = $sock->fileno;
	my $id  = $self->{filenoMap}{$fno};

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

sub activeWorkersCount {
	my ($self) = @_;
	my $supCnt = 0;
	foreach my $t (@{ $self->{workers} }) {
		my $queue = $self->{workerQueue}{ $t->tid };
		lock($queue);

		$supCnt++ unless $t->is_suspended() && !@$queue;
	}
	return $supCnt;
}

sub closingConnectionsCount {
	my ($self) = @_;
	my ($closeCnt, @list) = 0;
	{
		lock($self->{closeQueue});
		@list = keys %{ $self->{closeQueue} };
	}
	foreach (@list) {
		my $queue = $self->{responseQueue}{$_};
		if (!$queue) {
			$closeCnt++;
			next;
		}
		lock($queue);
		$closeCnt++ if !@$queue;
	}
	return $closeCnt;
}

sub send {
	my ($self, $sock, $msg) = @_;
	my $fno = $self->{filenoMap}{ $sock->fileno };
	if ($fno) {
		my $queue = $self->{responseQueue}{$fno};
		lock($queue);
		push @$queue, $msg;
	}
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

sub hasJobs {
	my ($self) = @_;
	my $queue = $self->{jobQueue};
	lock($queue);

	return @$queue > 0;
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

	$self->delegateToWorker(undef, $job);
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
		@jobs   = @$queue;
		@$queue = ("exitWorker");
	}

	$t->resume if $t->is_suspended;

	delete $self->{workerQueue}{$tid};
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

	$self->log("Saving state ...");

	$self->removeExecutor;

	# TODO: find a way to save waiting jobs something with the waiting jobs
	# the problem is that they are per connection and when connections are lost these jobs are meaning full
	$self->removeWorker($_) foreach @{ $self->{workers} };

	# wait for threads to stop
	sleep 1;

	# my @jobs;
	# push @jobs, @{ $self->removeWorker($_) } foreach @{ $self->{workers} };
	# {
	# my $queue = $self->{jobQueue};
	# lock($queue);

	# push @jobs, @$queue;
	# }

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
		{ map { +$_ => $self->{$_} } qw(persists persistsByType persistLookup delayedEvents jobQueue) });

	my $cfg  = $self->{config}{server};
	my $path = "$cfg->{tmp}/$cfg->{name}-state.res";
	$self->log("Writing $path to disk");
	Storable::store($data, $path);

	$self->log("Bye bye");

	# waiting for loggers to catch up
	sleep 1;

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
	return unless $self->{config}{debugMode};

	my $path = "$self->{config}{server}{logger}{path}/messages.log";
	unlink $path if $self->{debugMessageCount} > 0 && !($self->{debugMessageCount} % 100_000);
	$self->{debugMessageCount}++;

	open FW, ">>$path";
	print FW time." $msg\n";
	close FW;

	return;
}

1;
