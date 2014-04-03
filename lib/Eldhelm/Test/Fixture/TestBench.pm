package Eldhelm::Test::Fixture::TestBench;

use strict;
use threads;
use threads::shared;
use Carp;
use Eldhelm::Util::Factory;
use Eldhelm::Test::Mock::Worker;
use Eldhelm::Test::Mock::Connection;
use Eldhelm::Test::Mock::Session;

sub new {
	my ($class, %args) = @_;

	my $self = {};
	bless $self, $class;

	$self->{config} = shared_clone($args{config} || {});
	$self->{worker} = Eldhelm::Test::Mock::Worker->new(
		config => $self->{config},
		router => $args{router}
	);
	$self->{session} = Eldhelm::Test::Mock::Session->new($args{sessionArgs} ? %{ $args{sessionArgs} } : ());
	$self->{connection} = Eldhelm::Test::Mock::Connection->new(session => $self->{session});

	return $self;
}

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

sub connection {
	my ($self) = @_;
	return $self->{connection};
}

sub session {
	my ($self) = @_;
	return $self->{session};
}

1;
