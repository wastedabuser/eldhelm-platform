package Eldhelm::Server::Handler::Factory;

use strict;
use Eldhelm::Util::Factory;

sub new {
	my ($class, %args) = @_;
	my $self = { worker => $args{worker}, };
	bless $self, $class;

	return $self;
}

sub instance {
	my ($self, $type, %args) = @_;
	return Eldhelm::Util::Factory->instance("Eldhelm::Server::Handler::".ucfirst($type), %args);
}

1;
