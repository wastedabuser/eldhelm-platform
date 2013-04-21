package Eldhelm::Test::WorkerDummy;

use strict;
use warnings;
use threads;
use threads::shared;
use Data::Dumper;

use base qw(Eldhelm::Server::Child);

sub create {
	my (%args) = @_;
	Eldhelm::Server::Worker->new(%args);
}

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Child->instance;
	if (ref $self ne "Eldhelm::Server::Worker") {
		$self = Eldhelm::Server::Child->new(%args);
		bless $self, $class;

		$self->addInstance;
		
		$self->{persists} = shared_clone({});
		$self->{persistsByType} = shared_clone({});
		$self->{delayedEvents} = shared_clone({});
	}
	return $self;
}

1;