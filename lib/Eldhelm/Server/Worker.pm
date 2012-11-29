package Eldhelm::Server::Worker;

use strict;
use warnings;
use threads;
use threads::shared;
use Thread::Suspend;
use Eldhelm::Util::Factory;
use Eldhelm::Server::Handler::Factory;
use Data::Dumper;
use Time::HiRes qw(usleep);
use Carp;
use Carp qw(longmess);

use base qw(Eldhelm::Server::Child);

sub create {
	my (%args) = @_;
	Eldhelm::Server::Worker->new(%args);
}

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Child->instance;
	if (ref $self ne "Eldhelm::Server::Worker") {
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
	$self->{suspendWorkers} = $self->getConfig("server.suspendWorkers");
}

# =================================
# Tasks
# =================================

sub run {
	my ($self) = @_;
	my ($conn, $data);
	while (1) {
		($conn, $data) = $self->fetchTask;
		if ($conn && $conn eq "connectionError") {
			next;
		} elsif (!$data) {
			if ($self->{suspendWorkers}) {
				$self->suspend;
			} else {
				usleep(1000);
			}
			next;
		}
		$self->runTask($conn, $data);
	}
}

sub suspend {
	my ($self) = @_;
	$self->log("Will take a nap");
	threads->self()->suspend();
	$self->log("Ready to role");
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
	return () if !$task;

	if ($task eq "exitWorker") {
		$self->log("Exitting ...");
		threads->exit();
	}

	my $job;
	($self->{fno}, $job) = @$task;

	my $conn = $self->getConnection;
	if (!$conn && $job->{proto} ne "System") {
		$self->error("Can not process task, connection $self->{fno} is not available");
		return ("connectionError", $job);
	}

	$self->router({ connection => $conn })->clearErrors;
	return ($conn, $job);
}

sub runTask {
	my ($self, $conn, $data) = @_;
	my $handler = $self->createHandler($data->{proto}, %$data, worker => $self);
	if ($handler) {
		if ($handler->{composer}) {
			eval { $handler->setConnection($conn) };
			$self->error("Unable to set connection in handler: $@") if $@;
		}
		eval {
			$handler->handle;
			$self->sendData($handler->createResponse, undef, 1);
			$handler->finish;
		};
		$self->error("Handler error: $@") if $@;
	} else {
		$self->endTask;
	}
}

sub createHandler {
	my ($self, $type, %args) = @_;
	return if !$type;
	return $self->{handler} = Eldhelm::Server::Handler::Factory->instance($type, %args);
}

sub endTask {
	my ($self) = @_;
	$self->log("Closing");
	$self->closeConnection;
	return $self;
}

1;
