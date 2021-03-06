package Eldhelm::Server::Handler::System;

=pod

=head1 NAME

Eldhelm::Server::Handler::System

=head1 DESCRIPTION

This class parses C<ping> and C<echo> commands sent by a client.
They usually work with the L<Eldhelm::Server::Handler::Json> handler.

This class also handles internal server messaging for delays and events.

=head1 METHODS

=over

=cut

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

	my %parsed = (
		content       => $data,
		headerContent => ""
	);
	$data =~ s/^-(.+?)-//;

	# $data =~ s/^-([a-z0-9_]+?)-//;
	$parsed{command} = $1;
	$parsed{len}     = -1;

	return (\%parsed, $data);
}

# the class definition

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub handle {
	my ($self) = @_;
	my $fn = $self->{job};
	return unless $fn;
	
	$self->$fn();
}

sub handleAction {
	my ($self) = @_;
	$self->worker->status("task", "handleAction:$self->{action}");
	
	$self->router->doAction($self->{action}, $self->{data}, 1);
}

sub handleConnectionEvent {
	my ($self) = @_;
	$self->worker->status("task", "handleConnectionEvent:$self->{eventType}");
	
	$_->trigger($self->{eventType}, $self->{eventOptions})
		foreach $self->worker->findPersist("eventFno", $self->{eventFno});
}

sub handleDelayEvent {
	my ($self) = @_;
	my $event = $self->{data};
	$self->worker->status("task", "handleDelayEvent:$event->{handle}");

	my $persistId = $event->{persistId};
	if ($persistId) {
		my $persist = $self->worker->getPersist($persistId);
		$persist->doEvent($event) if $persist;
		return;
	}

	$self->router->executeAction($event->{handle}, $self, $event->{args});
}

sub evaluateCode {
	my ($self) = @_;
	$self->worker->status("task", "evaluateCode");
	
	confess "Nothing to evaluate" if !$self->{code};
	eval $self->{code};
	confess $@ if $@;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
