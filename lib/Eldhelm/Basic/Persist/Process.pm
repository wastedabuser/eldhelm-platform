package Eldhelm::Basic::Persist::Process;

=pod

=head1 NAME

Eldhelm::Basic::Persist::Process - A persistant object with a session context.

=head1 SYNOPSIS

In general you should inherit this class and cerate your own persistant object.
You can still use it as a general purpose object, but it is not advised.

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Util::Factory;
use Data::Dumper;

use base qw(Eldhelm::Basic::Persist);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->{session} = $args{session};

	return $self;
}

=item sessionContext() Eldhelm::Server::Session

Returns the L<Eldhelm::Server::Session> object that invoked the current execution.
Usually this when a clients talks to the server (executing actions) via a session. 

=cut

sub sessionContext {
	my ($self) = @_;
	$self->worker->{sessionContext};
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
