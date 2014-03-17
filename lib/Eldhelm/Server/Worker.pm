package Eldhelm::Server::Worker;

use strict;
use threads;
use threads::shared;
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
			$self->status("action", "wait");
			usleep(1000);
			next;
		}
		$self->runTask($conn, $data);
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
	return () if !$task;

	if ($task eq "exitWorker") {
		print "Exitting worker ".threads->tid()." ... \n";
		$self->status("action", "exit");
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
	$self->status("action", "run");
	my $handler = $self->createHandler($data->{proto}, %$data, worker => $self);
	if ($handler) {
		if ($handler->{composer}) {
			eval { $handler->setConnection($conn) };
			$self->error("Unable to set connection in handler: $@") if $@;
		}
		eval {
			$handler->handle;
			$handler->respond;
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
