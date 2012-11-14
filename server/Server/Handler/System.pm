package Eldhelm::Server::Handler::System;

use strict;
use Data::Dumper;
use Carp;

use base qw(Eldhelm::Server::Handler);

# static methods

sub check {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	return $data =~ m/^-[a-z0-9_]/i ? 1 : undef;
}

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;

	return ({ len => -2 }, $data) unless $data =~ m/[a-z0-9_]-/i;

	my %parsed;
	$data =~ s/^-(.+?)-//;
	$parsed{command} = $1;
	$parsed{len}     = -1;

	return (\%parsed, $data);
}

# the class definition

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Handler->new(%args);
	bless $self, $class;

	return $self;
}

sub handle {
	my ($self) = @_;
	my $fn = $self->{job};
	return if !$fn;
	$self->$fn();
}

sub handleAction {
	my ($self) = @_;
	$self->router->doAction($self->{action}, $self->{data}, 1);
}

sub handleConnectionEvent {
	my ($self) = @_;
	$_->trigger($self->{eventType}, $self->{eventOptions}) foreach $self->worker->findPersist("eventFno", $self->{eventFno});
}

sub handleDelayEvent {
	my ($self) = @_;
	my $persist = $self->worker->getPersist($self->{data}{persistId});
	$persist->doEvent($self->{data}) if $persist;
}

sub evaluateCode {
	my ($self) = @_;
	confess "Nothing to evaluate" if !$self->{code};
	eval $self->{code};
	confess $@ if $@;
}

1;
