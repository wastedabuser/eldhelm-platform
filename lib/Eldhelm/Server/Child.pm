package Eldhelm::Server::Child;

=pod

=head1 NAME

Eldhelm::Server::AbstractChild - A base class for a thread wrapper object that responds to messages.

=head1 SYNOPSIS

This class should not be constructed directly. This is a singleton object.

	Eldhelm::Server::Child->instance

=head1 METHODS

=over

=cut

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

use parent 'Eldhelm::Server::AbstractChild';

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
	confess('Status can not be a reference!') if ref $value;

	$status->{$name} = $value;
	return;
}

sub setWaitStatus {
	my ($self) = @_;
	my $status = $self->{workerStatus};
	lock($status);

	$status->{action} = 'wait';
	$status->{proto}  = '';
	$status->{task}   = '';
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
	return Eldhelm::Util::Factory->instanceFromScalar('Eldhelm::Server::Connection', $connData);
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

sub getAllConnectionCount {
	my ($self) = @_;
	my $cnt;
	{
		my $conns = $self->{connections};
		lock($conns);
		$cnt = keys %$conns;
	}
	return $cnt;
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
	$self->addDataToQueue($fno, shared_clone($event || { initiator => 'server' }));
	return;
}

sub doJob {
	my ($self, $job) = @_;
	if (!$job->{job}) {
		$self->error("Can not execute a job without a job name:\n".Dumper($job));
		return;
	}

	return $self->addDataToQueue(undef, shared_clone({ %$job, proto => 'System' }));
}

sub doActionInBackground {
	my ($self, $action, $data) = @_;
	return $self->doJob(
		{   job          => 'handleAction',
			action       => $action,
			data         => $data,
			priority     => 1,
			connectionId => $self->{fno}
		}
	);
}

=item delay($interval, $handle, $args, $persistId) String

Registers a task to be executed after a delay in seconds. Returns the id of the delayed taks.

C<$interval> Number - The delay interval in seconds;
C<$handle> - The controller action which will handle the task;
C<$args> - Context data to be send to the delayed task;
C<$persistId> - Optional; A persistant object to be used as a context;

=cut

sub delay {
	my ($self, $interval, $handle, $args, $persistId) = @_;
	return unless $handle;

	my $stamp = time + $interval;
	my $id    = $stamp.'-'.rand();

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

=item cancelDelay($delayId) 

Cancels a delay by it's id.

C<$delayId> String - the id of the delay;

=cut

sub cancelDelay {
	my ($self, $delayId) = @_;
	return $self->addDataToQueue(undef, shared_clone({ cancelDelayId => $delayId }));
}

# =================================
# Utility
# =================================

sub DESTROY {
	my ($self) = @_;
	$self->error('i am dead');
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
