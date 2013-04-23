package Eldhelm::Test::Mock::Socket;

use strict;

sub new {
	my ($class, $id) = @_;
	my $self = {
		fileno => $id,
	};
	return bless $self, $class;
}

sub fileno {
	my ($self) = @_;
	return $self->{fileno};
}

1;