package Eldhelm::Server::Executor;

use strict;
use threads;
use threads::shared;
use Eldhelm::Util::Tool;
use Eldhelm::Server::Shedule;
use Data::Dumper;
use Time::HiRes;
use Time::HiRes qw(time usleep);
use Date::Format;
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
		$self->run;
	}
	return $self;
}

sub init {
	my ($self) = @_;
	$self->{connectionTimeout} = $self->getConfig("server.connectionTimeout");
	$self->{keepaliveInterval} = $self->getConfig("server.keepaliveInterval");
	$self->{pingAvgSamples}    = (60 / $self->{keepaliveInterval}) * 10;
	$self->{interval}          = 25_000;
	$self->{sheduled} =
		[ map { Eldhelm::Server::Shedule->new(init => $_) }
			Eldhelm::Util::Tool->toList($self->getConfig("server.shedule.action")) ];
}

# =================================
# Tasks
# =================================

sub run {
	my ($self) = @_;
	my ($lastSecTime, $lastTenSecTime, $kaTime, $curTime) = (time, time);
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
			$self->checkTimeout;
			$self->checkShedule;

			$lastSecTime = time;
		}

		# every 10 seconds
		if ($curTime - $lastTenSecTime >= 10) {
			$self->checkConnectionTimeout;

			$lastTenSecTime = time;
		}

		# keepalive intervals
		if ($curTime - $kaTime >= $self->{keepaliveInterval}) {
			$self->pingConnections;

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
		$self->log("Exitting ...");
		threads->exit();
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

	foreach my $p (@persists) {
		lock($p);

		my $hasTo = ($tm >= $p->{updatedon} + $p->{timeout});
		next unless $hasTo;

		my $id = $p->{id};
		if ($p->{persistType} eq "Eldhelm::Server::Session") {
			$self->cleanUp($id) unless $p->{connected};
		} else {
			$self->cleanUp($id);
		}
	}
}

sub cleanUp {
	my ($self, $id) = @_;
	my $persist = $self->getPersist($id);
	return if !$persist;
	$self->log("Timeout for '$id' - ".ref $persist);
	$persist->dispose;
}

sub checkShedule {
	my ($self) = @_;
	my $list = $self->{sheduled};
	return if !$list;

	foreach (@$list) {
		next unless $_->isTime;
		$self->doJob($_->job);
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
			$self->debug("Ping for $fno from $c->{peerhost} is $c->{ping} ($c->{avgPing})");
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
	lock($evs);

	my @ids = keys %$evs;
	return if !@ids;
	foreach my $id (@ids) {
		my $triggers = $evs->{$id};
		lock($triggers);

		my @trigs = keys %$triggers;
		foreach my $type (@trigs) {
			$self->doJob(
				{   job          => "handleConnectionEvent",
					eventType    => $type,
					eventFno     => $id,
					eventOptions => delete $triggers->{$type},
				}
			);
		}
		delete $evs->{$id} if !keys %$triggers;
	}
}

sub triggerDelayedEvents {
	my ($self) = @_;
	my $devs = $self->{delayedEvents};
	lock($devs);

	my @stamps = keys %$devs;
	return if !@stamps;
	my ($now, $list) = (time);
	foreach my $st (@stamps) {
		next if $now < $st;
		$self->debug("Delayed for $st");
		next if !@{ $devs->{$st} };
		$list = delete $devs->{$st};
		foreach my $ev (@$list) {
			next if $ev->{canceled};
			$self->doJob(
				{   job  => "handleDelayEvent",
					data => $ev,
				}
			);
		}
		$self->debug("Done delayed for $st");
	}
}

# =================================
# Utility
# =================================

sub log {
	my ($self, $msg, $type) = @_;
	$type ||= "general";
	my $queue = $self->{logQueue}{$type};
	return if !$queue;

	lock($queue);
	my $tm = time;
	push @$queue, "~$tm~Executor: $msg";
	return $self;
}

1;
