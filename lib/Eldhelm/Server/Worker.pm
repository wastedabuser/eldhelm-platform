package Eldhelm::Server::Worker;

=pod

=head1 NAME

Eldhelm::Server::Worker - A wrapper class for a wroker thread.

=head1 SYNOPSIS

This class should not be constructed directly. It is accessed via the C<worker> getter in various contexts.

	Eldhelm::Basic::Controler->worker;
	Eldhelm::Basic::Model->worker;
	Eldhelm::Basic::Persist->worker;
	# etc.

=head1 METHODS

=over

=cut

use strict;

use threads;
use threads::shared;
use Eldhelm::Util::Factory;
use Eldhelm::Server::Handler::Factory;
use Data::Dumper;
use Time::HiRes qw(usleep time);
use Carp qw(confess longmess);

use parent 'Eldhelm::Server::Child';

sub create {
	my (%args) = @_;
	Eldhelm::Server::Worker->new(%args);
}

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Child->instance;
	if (ref $self ne 'Eldhelm::Server::Worker') {
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
	$self->{maxTaskTime}  = $self->getConfig('server.logger.slowLogTime');
	$self->{maxTaskTimeU} = $self->getConfig('server.logger.slowLogTimeU') || $self->{maxTaskTime};
	$self->{maxTaskTimeR} = $self->getConfig('server.logger.slowLogTimeR') || $self->{maxTaskTime};
}

=item getServerStat($name) 

Returns a server stat by name

C<$name> String - the name of the stat;

The following names are available:
C<workerStatus> - A worker status string;
C<averageHpsAll> - Average hits per second for all protocols;
C<averageHpsHttp> - Average hits per second for a specific protocol. Might be Http or Base64 etc.;

=cut

sub getServerStat {
	my ($self, $name) = @_;
	my $stats = $self->{serverStats};
	lock($stats);
	return $stats->{$name};
}

=item getTaskElapsedTime

Returns the elapsed time executing the current task in seconds

=cut

sub getTaskElapsedTime {
	my ($self) = @_;
	return time - $self->{taskStartTime};
}

=item getTaskElapsedTimeMs

Returns the elapsed time executing the current task in miliseconds

=cut

sub getTaskElapsedTimeMs {
	my ($self) = @_;
	return (time - $self->{taskStartTime}) * 1000;
}

# =================================
# Tasks
# =================================

sub run {
	my ($self) = @_;
	my ($conn, $data);
	while (1) {
		($conn, $data) = $self->fetchTask;
		if ($conn && $conn eq 'connectionError') {
			next;
		} elsif (!$data) {
			$self->setWaitStatus;
			usleep(5000);
			next;
		}

		$self->{taskStartTime} = time;
		$self->runTask($conn, $data);
		my $maxTime  = $self->{ 'maxTaskTime'.$self->{workerType} };
		my $execTime = $self->getTaskElapsedTime;
		if ($maxTime > 0 && $execTime > $maxTime) {
			$self->log('A worker task took '.sprintf('%.4f', $execTime).' seconds: '.Dumper($data), 'slow');
		}

		threads->yield();
	}
}

sub fetchTask {
	my ($self) = @_;
	my $task;
	{
		my $queue = $self->{workerQueue};
		lock($queue);

		my $ln = scalar(@$queue);
		return () unless $ln;

		$self->log("Fetching (queue length $ln)");
		$task = shift @$queue;
	}
	return () unless $task;

	unless (ref $task) {
		$self->exitWorker if $task eq 'exitWorker';
		$self->reconfig   if $task eq 'reconfig';
		return ();
	}

	my $job;
	($self->{fno}, $job) = @$task;

	my $conn = $self->getConnection;
	if (!$conn && $job->{proto} ne 'System') {
		$self->error("Can not process task, connection $self->{fno} is not available");
		return ('connectionError', $job);
	}

	$self->router({ connection => $conn })->clearErrors;
	return ($conn, $job);
}

sub runTask {
	my ($self, $conn, $data) = @_;
	$self->status('action', 'run');
	$self->status('proto',  $data->{proto});
	my $handler = $self->createHandler($data->{proto}, %$data);
	if ($handler) {
		if ($handler->{composer}) {
			eval {
				$handler->setConnection($conn);
				1;
			} or do {
				$self->error("Unable to set connection in handler: $@");
			};
		}
		eval {
			$handler->handle;
			$handler->respond;
			$handler->finish;
			1;
		} or do {
			$self->error("Handler error: $@");
		};
	} else {
		$self->endTask;
	}
}

sub createHandler {
	my ($self, $type, %args) = @_;
	return unless $type;
	return $self->{handler} = Eldhelm::Server::Handler::Factory->instance($type, %args, worker => $self);
}

sub endTask {
	my ($self) = @_;
	$self->log('Closing');
	$self->closeConnection;
	return $self;
}

sub exitWorker {
	my ($self) = @_;
	print 'Exitting worker '.threads->tid()." ... \n";
	$self->status('action', 'exit');
	usleep(10_000);
	threads->exit();
}

sub reconfig {
	my ($self) = @_;
	print 'Reconfiguring worker '.threads->tid()." ... \n";
	$self->init;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
