package Eldhelm::Test::Mock::Worker;

use strict;
use threads;
use threads::shared;
use Data::Dumper;
use Eldhelm::Test::Mock::Session;

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

		$self->{config}         = is_shared($args{config}) ? $args{config} : shared_clone($args{config} || {});
		$self->{persists}       = shared_clone({});
		$self->{persistsByType} = shared_clone({});
		$self->{persistLookup}  = shared_clone({});
	}
	return $self;
}

sub error {
	my ($self, $msg) = @_;
	warn "# $msg";
}

sub createTestSession {
	my ($self, $args) = @_;
	my $s = Eldhelm::Test::Mock::Session->new(%$args);
	$self->{testSessions}{ $s->id } = $s;
	return $s;
}

sub getPersist {
	my ($self, $id) = @_;
	return if !$id;

	return $self->{testSessions}{$id};
}

1;
