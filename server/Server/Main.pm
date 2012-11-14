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
			info                => { version => "1.1.0" },
			ioSocketList        => [],
			config              => {},
			workers             => [],
			workerQueue         => {},
			connId              => 1,
			connidMap           => {},
			filenoMap           => {},
			streamMap           => {},
			buffMap             => {},
			connectionHandles   => {},
			connections         => shared_clone({}),
			connectionEvents    => shared_clone({}),
			delayedEvents       => shared_clone({}),
			responseQueue       => shared_clone({}),
			closeQueue          => shared_clone({}),
			persists            => shared_clone({}),
			persistsByType      => shared_clone({}),
			persistLookup       => shared_clone({}),
			workerStats         => {},
			connectionWorkerMap => {},
			jobQueue            => shared_clone([]),
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
	@listen = map { { host => $_->{host} || $cnf->{host}, port => $_->{port} || $cnf->{port} } } @{ $cnf->{listen} }
		if ref $cnf->{listen};
	foreach ($cnf, @listen) {
		my ($h, $p) = ($_->{host}, $_->{port});
		next if !$h || !$p;

		push @{ $self->{ioSocketList} },
			IO::Socket::INET->new(
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

	$self->{ioSelect} = IO::Select->new(@{ $self->{ioSocketList} }) || die "IO::Select $!\n";

	# start the executor
	$self->createExecutor;

	# start workers
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
		$self->error("Server shutting down by user command");
		$self->saveStateAndShutDown;
	};

	$SIG{KILL} = sub {
		my $sig = shift @_;
		$self->error("Server shutting down by kill command");
		$self->saveStateAndShutDown;
	};
	
	$SIG{TERM} = sub {
		my $sig = shift @_;
		$self->error("Server shutting down by term command");
		$self->saveStateAndShutDown;
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
			qw(config info logQueue connections responseQueue closeQueue persists persistsByType persistLookup delayedEvents connectionEvents jobQueue)
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
			qw(config info logQueue connections responseQueue closeQueue persists persistsByType persistLookup delayedEvents jobQueue)
	);
	$self->log("Created worker: ".$t->tid);
	$self->{workerQueue}{ $t->tid } = $workerQueue;
	$self->{workerStats}{ $t->tid }{jobs} = 0;
	$t->detach();
	push @{ $self->{workers} }, $t;
	return;
}

sub listen {
	my ($self) = @_;

	my ($socketList, $select, $config, $acceptFlag, $hasWork, $hasPending, $data, @clients) =
		($self->{ioSocketList}, $self->{ioSelect}, $self->{config}{server});
	$self->log("Eldhelm server ready and listening ...");

	while (1) {

		$hasWork = $self->activeWorkersCount;
		usleep(5000 * $hasWork) if !$config->{multicore} && $hasWork;

		$self->message("will read from socket");
		@clients =
			$select->can_read($hasPending || $hasWork || $self->closingConnectionsCount || $self->hasJobs ? 0 : .004);
		foreach my $fh (@clients) {
			$acceptFlag = 0;
			foreach my $socket (@$socketList) {
				next unless $fh == $socket;
				my $conn = $socket->accept();
				$self->createConnection($conn);
				$self->configConnection($conn);
				$acceptFlag = 1;
			}

			next if $acceptFlag;
			$currentFh = $fh;
			$data      = "";
			$fh->recv($data, POSIX::BUFSIZ, 0);    # 65536
			unless (defined($data) && length $data) {
				$self->removeConnection($fh, "remote");
			} else {
				$self->monitorConnection($fh, \$data);
				$self->addToStream($fh, $data);
			}
		}

		$hasPending = 0;
		@clients    = $select->can_write(0);
		$self->message("can write to socket ".scalar @clients);
		my $h = 0;
		foreach my $fh (@clients) {
			$self->message("write to $h");
			my $fileno = $fh->fileno;
			my $fno    = $self->{filenoMap}{$fileno};
			my $queue  = $self->{responseQueue}{$fno};

			$self->message("lock $h");
			lock($queue);
			$self->message("sending $h");
			if (@$queue) {
				if ($fh->connected) {
					$self->message("do send $h");
					shift @$queue unless length ${ $self->sendToSock($fh, \$queue->[0]) };
				} else {
					$self->error("A connection error occured while sending to $fno($fileno)");
					$self->message("remove $h");
					$self->removeConnection($fh, "unknown");
					$self->message("removed $h");
				}
			}
			$self->message("writen to $h");

			$h++;
			$hasPending = 1 if @$queue;
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
			if (!$queue || !@$queue) {
				$self->message("remove $h");
				$self->removeConnection($_, "server");
				$self->message("removed $h");
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
		$charCnt = $fh->send($$data, 0);
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
			{   fno            => $id,
				fileno         => $fileno,
				peeraddr       => $sock->peeraddr,
				peerport       => $sock->peerport,
				peerhost       => $sock->peerhost,
				sockaddr       => $sock->sockaddr,
				sockport       => $sock->sockport,
				sockhost       => $sock->sockhost,
				recvLength     => 0,
				connected      => 1,
				connectedOn    => time,
				avgPingSamples => [],
			}
		);
	}

	{
		lock($self->{responseQueue});
		$self->{responseQueue}{$id} = shared_clone([]);
	}

	$self->log("Connection $id($fileno) from ".$sock->peerhost." open", "access");
}

sub configConnection {
	my ($self, $sock) = @_;

	$sock->autoflush(1);

	if (!$isWin) {
		use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
		my $flags = $sock->fcntl(F_GETFL, 0) or die "Can't get flags for the socket: $!\n";
		$sock->fcntl(F_SETFL, O_NONBLOCK) or die "Can't set flags for the socket: $!\n";
	} else {
		IO::Handle::blocking($sock, 0);
	}
}

sub monitorConnection {
	my ($self, $sock, $data) = @_;
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
	delete $self->{connectionWorkerMap}{$id};

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

	if (ref $event) {
		$self->registerConnectionEvent("disconnect", $event, $id);
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
	if ($cmd eq "ping") {
		lock($self->{connections});

		my $conn = $self->{connections}{$id};
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
	$t->resume if $t->is_suspended;

	return;
}

sub selectWorker {
	my ($self, $id) = @_;

	my ($chosen, @list);
	$chosen = $self->{connectionWorkerMap}{$id} if $id;

	foreach my $t (@{ $self->{workers} }) {
		my $isSusp = $t->is_suspended;
		$chosen = $t if !$chosen && $isSusp;
		my $tid = $t->tid;
		push @list,
			{
			tid    => $tid,
			status => $isSusp ? "_" : "W",
			size   => scalar @{ $self->{workerQueue}{$tid} },
			trd    => $t
			};

	}
	$self->log(
		"Worker load: ["
			.join(", ",
			map { "$_->{tid}:$_->{status}:$_->{size}\($self->{workerStats}{$_->{tid}}{jobs}\)" } @list)
			."]"
	);
	$chosen = [ sort { $a->{size} <=> $b->{size} } @list ]->[0]{trd}
		if !$chosen;

	$self->{connectionWorkerMap}{$id} ||= $chosen if $id;

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

1;
