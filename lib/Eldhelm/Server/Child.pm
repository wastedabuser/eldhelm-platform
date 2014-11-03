package Eldhelm::Server::Child;

use strict;
use threads;
use threads::shared;
use Data::Dumper;
use Time::HiRes;
use Carp;
use Carp qw(longmess);
use Eldhelm::Util::Factory;
use Eldhelm::Server::Router;
use Eldhelm::Util::Tool;

use base qw(Eldhelm::Server::AbstractChild);

sub new {
	my ($class, %args) = @_;

	my $self = bless {
		fno => undef,
		id  => threads->tid,
		%args
	}, $class;

	$self->{router} ||= Eldhelm::Server::Router->new;

	return $self;
}

sub status {
	my ($self, $name, $value) = @_;
	my $status = $self->{workerStatus};
	lock($status);

	return $status->{$name} unless defined $value;

	$status->{$name} = $value;
	return;
}

sub getConnection {
	my ($self, $fno) = @_;

	$fno ||= $self->{fno};
	return if !$fno;

	my $connData;
	{
		my $conns = $self->{connections};
		lock($conns);

		$connData = $conns->{$fno};
	}
	return if !$connData;

	lock($connData);
	return Eldhelm::Util::Factory->instanceFromScalar("Eldhelm::Server::Connection", $connData);
}

sub getAllConnections {
	my ($self) = @_;
	my @connections;
	{
		my $conns = $self->{connections};
		lock($conns);

		@connections = values %$conns;
	}
	return [] unless @connections;

	my @list;
	foreach my $conn (@connections) {
		lock($conn);

		push @list, Eldhelm::Util::Tool::cloneStructure($conn);
	}
	return \@list;
}

sub router {
	my ($self, $config) = @_;
	$self->{router}->config($config) if $config;
	return $self->{router};
}

sub addDataToQueue {
	my ($self, $fno, $data) = @_;
	my $queue = $self->{responseQueue};
	lock($queue);

	push @$queue, $fno, $data;
	return $self;
}

sub sendFile {
	my ($self, $data, $path, $ln, $fno) = @_;
	$self->sendData($data) if $data;

	return $self unless $path;

	$fno ||= $self->{fno};
	$self->log("Responding $path to $fno");

	return $self->addDataToQueue($fno, shared_clone({ file => $path, ln => $ln }));
}

sub sendData {
	my ($self, $data, $fno) = @_;

	return $self unless $data;

	$fno ||= $self->{fno};
	my $ln = length($data);
	$self->log("Responding ($ln bytes) to $fno");

	return $self->addDataToQueue($fno, $data);
}

sub closeConnection {
	my ($self, $fno, $event) = @_;
	$fno ||= $self->{fno};
	$self->addDataToQueue($fno, shared_clone($event || { initiator => "server" }));
	return;
}

sub doJob {
	my ($self, $job) = @_;
	if (!$job->{job}) {
		$self->error("Can not execute a job without a job name:\n".Dumper($job));
		return;
	}

	return $self->addDataToQueue(undef, shared_clone({ %$job, proto => "System" }));
}

sub doActionInBackground {
	my ($self, $action, $data) = @_;
	return $self->doJob(
		{   job          => "handleAction",
			action       => $action,
			data         => $data,
			priority     => 1,
			connectionId => $self->{fno}
		}
	);
}

sub delay {
	my ($self, $interval, $handle, $args, $persistId) = @_;
	return unless $handle;

	my $stamp = time + $interval;
	my $id    = $stamp."-".rand();

	$self->addDataToQueue(
		undef,
		shared_clone(
			{   persistId => $persistId,
				delayId   => $id,
				stamp     => $stamp,
				handle    => $handle,
				args      => $args,
			}
		)
	);

	return $id;
}

sub cancelDelay {
	my ($self, $delayId) = @_;
	return $self->addDataToQueue(undef, shared_clone({ cancelDelayId => $delayId }));
}

# =================================
# Utility
# =================================

sub DESTROY {
	my ($self) = @_;
	$self->error("i am dead");
}

1;
