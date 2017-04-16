package Eldhelm::Server::Executor;

use strict;
use threads;
use threads::shared;
use Eldhelm::Util::Tool;
use Eldhelm::Util::Factory;
use Eldhelm::Server::Schedule;
use Data::Dumper;
use Time::HiRes;
use Time::HiRes qw(time usleep);
use Date::Format;
use Digest::MD5 qw(md5_hex);
use Carp;

use base qw(Eldhelm::Server::Child);

sub create {
	my (%args) = @_;
	Eldhelm::Server::Executor->new(%args);
}

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Child->instance;
	if (ref $self ne "Eldhelm::Server::Executor") {
		$self = Eldhelm::Server::Child->new(%args);
		bless $self, $class;

		$self->addInstance;
		$self->init;
		$self->initSchedule;
		$self->run;
	}
	return $self;
}

sub init {
	my ($self) = @_;
	$self->{connectionTimeout} = $self->getConfig("server.connectionTimeout") || 600;
	$self->{keepaliveInterval} = $self->getConfig("server.keepaliveInterval") || 20;
	$self->{pingAvgSamples}    = (60 / $self->{keepaliveInterval}) * 10;
	$self->{interval}          = 100_000;
}

sub initSchedule {
	my ($self) = @_;

	my $listed = $self->getConfig("server.schedule.action")      || [];
	my $named  = $self->getConfig("server.schedule.namedAction") || {};

	my $i = 0;
	foreach (@$listed) {
		$named->{"unnamed-schedule-$i"} = $_;
		$i++;
	}

	my $se = $self->{scheduledEvents};
	lock($se);

	$self->{scheduledObjects} ||= {};
	foreach my $id (keys %$named) {
		my $obj = $named->{$id};
		$se->{$id} = shared_clone(
			{   name    => $id,
				schedule => $obj->[0],
				action  => $obj->[1],
				data    => $obj->[2],
			}
		);
	}
}

# =================================
# Tasks
# =================================

sub run {
	my ($self) = @_;
	my ($lastSecTime, $lastTenSecTime, $kaTime, $curTime) = (time, time);
	$self->status("action", "run");

	while (1) {
		$curTime = time;

		# check the task queue
		$self->fetchTask;

		# connection events
		eval {
			$self->triggerConnectionEvents;
			$self->triggerDelayedEvents;
		};
		$self->error($@) if $@;

		# every second
		if ($curTime - $lastSecTime >= 1) {
			eval {
				$self->checkTimeout;
				$self->checkSchedule;
			};
			$self->error($@) if $@;

			$lastSecTime = time;
		}

		# every 10 seconds
		if ($curTime - $lastTenSecTime >= 10) {
			eval { $self->checkConnectionTimeout; };
			$self->error($@) if $@;

			$lastTenSecTime = time;
		}

		# keepalive intervals
		if ($curTime - $kaTime >= $self->{keepaliveInterval}) {
			eval { $self->pingConnections; };
			$self->error($@) if $@;

			$kaTime = time;
		}

		usleep($self->{interval});
	}
}

sub fetchTask {
	my ($self) = @_;
	my $task;
	{
		my $queue = $self->{workerQueue};
		lock($queue);

		$task = shift @$queue;
	}
	return if !$task;

	if ($task eq "exitWorker") {
		print "Exitting executor ...\n";
		$self->status("action", "exit");
		usleep(10_000);
		threads->exit();
	}

	if ($task eq "reconfig") {
		print "Reconfiguring executor ...\n";
		$self->init;
	}

	return;
}

sub checkTimeout {
	my ($self) = @_;
	my ($tm, @persists) = (time);
	{
		my $ref = $self->{persists};
		lock($ref);

		@persists = values %$ref;
	}
	return unless @persists;

	CHLP: foreach my $p (@persists) {
		my ($id, $type);
		{
			lock($p);

			my $hasTo = ($tm >= $p->{updatedon} + $p->{timeout}) || $p->{_forceDispose_};
			next CHLP unless $hasTo;

			($id, $type) = ($p->{id}, $p->{persistType});
		}

		if ($type eq "Eldhelm::Server::Session") {
			$self->cleanUpSession($id);
		} else {
			$self->cleanUp($id);
		}
	}
}

sub cleanUp {
	my ($self, $id) = @_;
	my $persist = $self->getPersist($id);
	unless ($persist) {
		$self->error("Unable to cleanup persist '$id'");
		return;
	}
	$self->log("Timeout for persist '$id' - ".ref $persist);
	$persist->dispose;
	return 1;
}

sub cleanUpSession {
	my ($self, $id) = @_;
	my $sess = $self->getPersist($id);
	unless ($sess) {
		$self->error("Unable to cleanup session '$id'");
		return;
	}
	return if $sess->connected;

	$self->log("Timeout for session '$id' - ".ref $sess);
	$sess->disposeWithReason('timeout');
	return 1;
}

sub checkSchedule {
	my ($self) = @_;
	my $so = $self->{scheduledObjects};
	return unless $so;

	my @list;
	{
		my $se = $self->{scheduledEvents};
		lock($se);
		@list = map { [ $_, $se->{$_} ] } keys %$se;
	}

	foreach (@list) {
		my ($k, $v, $id) = @$_;
		{
			lock($v);
			$id = $v->{uid} ||= md5_hex(rand().time);
		}
		my $s = $so->{$id} ||= Eldhelm::Util::Factory->instanceFromScalar("Eldhelm::Server::Schedule", $v)->init;

		next unless $s->isTime;
		$self->doJob($s->job);
	}

	my @objs = keys %$so;
	foreach (@objs) {
		my $sobj = $so->{$_};
		if ($sobj->get("disposed")) {
			my ($n, $s, $a, $u) = $sobj->getList("name", "schedule", "action", "uid");
			$self->log("cleaning up schedule $u($n) for $s $a");
			delete $so->{$_};
		}
	}
}

sub checkConnectionTimeout {
	my ($self) = @_;
	my @connections;
	{
		my $conns = $self->{connections};
		lock($conns);

		@connections = values %$conns;
	}
	return unless @connections;

	my ($ct, $to) = (time, $self->{connectionTimeout});

	foreach my $c (@connections) {
		lock($c);

		next if $c->{keepalive};
		next if $c->{lastActivityTime} + $to > $ct;

		my $fno = $c->{fno};
		$self->closeConnection(
			$fno,
			{   reason    => "connectionTimeout",
				initiator => "server",
			},
		);
		$self->log("Connection timeout for $fno");
	}

}

sub pingConnections {
	my ($self) = @_;
	my @connections;
	{
		my $conns = $self->{connections};
		lock($conns);

		@connections = values %$conns;
	}
	return unless @connections;

	foreach my $c (@connections) {
		lock($c);

		next unless $c->{keepalive};

		my $fno = $c->{fno};
		if ($c->{timeSample1} && !$c->{timeSample2}) {
			$self->closeConnection(
				$fno,
				{   reason    => "keepaliveTimeout",
					avgPing   => $c->{avgPing},
					initiator => "server",
				},
			);
			$self->log("Connection keepalive timeout for $fno");
			next;
		}

		if ($c->{timeSample1}) {
			$c->{ping} = int(($c->{timeSample2} - $c->{timeSample1}) * 1000);
			$self->calcAvgPing($c);
			$self->log("Ping for $fno from $c->{peerhost} is $c->{ping} ($c->{avgPing})");
		}

		$c->{timeSample1} = time;
		$c->{timeSample2} = 0;

		$self->sendData("-ping-", $fno);
	}
}

sub calcAvgPing {
	my ($self, $c) = @_;
	my $slist = $c->{avgPingSamples};
	my $sum   = $c->{avgPingSamplesSum} + $c->{ping};
	push @$slist, $c->{ping};
	if ($self->{pingAvgSamples} <= $c->{totalSamples}) {
		$sum -= shift @$slist;
	} else {
		$c->{totalSamples}++;
	}
	$c->{avgPingSamplesSum} = $sum;
	$c->{avgPing} = sprintf("%.2f", $sum / $c->{totalSamples});
}

sub triggerConnectionEvents {
	my ($self) = @_;

	my $evs = $self->{connectionEvents};
	my @jobs;
	{
		lock($evs);
		my @ids = keys %$evs;
		return unless @ids;

		foreach my $id (@ids) {
			my $triggers = $evs->{$id};
			lock($triggers);

			my @trigs = keys %$triggers;
			foreach my $type (@trigs) {
				push @jobs,
					{
					eventType    => $type,
					eventFno     => $id,
					eventOptions => delete $triggers->{$type}
					};
			}
			delete $evs->{$id} if !keys %$triggers;
		}
	}

	foreach my $ev (@jobs) {
		$self->doJob(
			{   job => "handleConnectionEvent",
				%$ev,
			}
		);
	}
}

sub triggerDelayedEvents {
	my ($self) = @_;

	my $devs = $self->{delayedEvents};
	my @jobs;
	{
		lock($devs);
		my @stamps = keys %$devs;
		return unless @stamps;

		my $now = time;
		foreach my $st (@stamps) {
			next if $now < $st;
			$self->log("Delayed for $st");
			next unless @{ $devs->{$st} };
			push @jobs, @{ delete $devs->{$st} };
			$self->log("Done delayed for $st");
		}
	}

	foreach my $ev (@jobs) {
		my $data;
		{
			lock($ev);
			next if $ev->{canceled};
			$data = Eldhelm::Util::Tool->cloneStructure($ev);
		}
		$self->doJob(
			{   job  => "handleDelayEvent",
				data => $data,
			}
		) if $data;
	}
}

# =================================
# Utility
# =================================

sub log {
	my ($self, $msg, $type) = @_;
	$type ||= "general";
	my $queue = $self->{logQueue}{$type};
	return unless $queue;

	lock($queue);
	my $tm = time;
	push @$queue, "~$tm~Executor: $msg";
	return $self;
}

1;
