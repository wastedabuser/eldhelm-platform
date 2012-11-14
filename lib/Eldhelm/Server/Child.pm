package Eldhelm::Server::Child;

use strict;
use warnings;
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

	$self->{router} = Eldhelm::Server::Router->new(config => $self->getConfig("server.router"));

	return $self;
}

sub getConfig {
	my ($self, $property) = @_;
	my $ref = $self->{config};
	my @chunks = split /\./, $property;
	$ref = $ref->{$_} foreach @chunks;
	return $ref;
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

sub sendData {
	my ($self, $data, $fno, $chunked) = @_;

	return $self if !$data;

	$fno ||= $self->{fno};

	my $ln = length($data);
	$self->log("Responding ($ln bytes) to $fno");

	my $queue;
	{
		lock($self->{responseQueue});
		$queue = $self->{responseQueue}{$fno};
	}

	if (!$queue) {
		$self->error("Can not send data to $fno, may be the connection dropped.");
		return $self;
	}
	lock($queue);

	return $chunked ? $self->addDataToQueueChunked($queue, $data, $fno) : $self->addDataToQueue($queue, $data, $fno);
}

sub addDataToQueue {
	my ($self, $queue, $data, $fno) = @_;
	eval { push @$queue, $data };
	$self->error(longmess "Error putting data via '$fno': $@\n".Dumper($data)) if $@;
	return $self;
}

sub addDataToQueueChunked {
	my ($self, $queue, $data, $fno) = @_;

	my $ln = length($data);
	my ($cs, $i) = (65536, 0);
	if ($ln <= $cs) {
		$self->addDataToQueue($queue, $data);
	}

	while (1) {
		my $pos    = $i * $cs;
		my $remain = $ln - $pos;
		last if $remain < 1;
		my $size = $remain > $cs ? $cs : $remain;
		my $chunk = substr $data, $pos, $size;
		eval { push @$queue, $chunk };
		$self->error(longmess "Error putting data via '$fno': $@") if $@;
		$i++;
	}

	return $self;
}

sub closeConnection {
	my ($self, $fno, $event) = @_;
	$fno ||= $self->{fno};
	lock($self->{closeQueue});

	$self->{closeQueue}{$fno} = $event ? shared_clone($event) : 1;
	return;
}

sub doJob {
	my ($self, $job) = @_;
	if (!$job->{job}) {
		$self->error("Can not execute a job without a job name:\n".Dumper($job));
		return;
	}

	my $queue = $self->{jobQueue};
	lock($queue);

	push @$queue, shared_clone({ %$job, proto => "System" });

	return $self;
}

# =================================
# Utility
# =================================

sub DESTROY {
	my ($self) = @_;
	$self->error("i am dead");
}

1;
