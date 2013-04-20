package Eldhelm::Test::SocketDummy;

use strict;

sub new {
	my ($class) = @_;
	my $self = {};
	return bless $self, $class;
}

sub fileno {
	return 1;
}

1;