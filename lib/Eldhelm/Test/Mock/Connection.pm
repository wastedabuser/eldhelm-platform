package Eldhelm::Test::Mock::Connection;

use strict;
use Data::Dumper;

use base qw(Eldhelm::Server::BaseObject);

sub new {
	my ($class, %args) = @_;
	my $self = { %args };
	bless $self, $class;

	return $self;
}

sub getSession {
	my ($self) = @_;
	return $self->{session};
}

sub say {
	my ($self, $data) = @_;
	$self->getSession->say($data);
}

sub sendHeader {
	
}

1;
