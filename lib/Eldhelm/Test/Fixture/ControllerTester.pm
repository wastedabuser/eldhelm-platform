package Eldhelm::Test::Fixture::ControllerTester;

use strict;
use Carp;
use Eldhelm::Util::Factory;
use Eldhelm::Test::Mock::Worker;
use Eldhelm::Test::Mock::Connection;
use Eldhelm::Test::Mock::Session;

sub new {
	my ($class, %args) = @_;

	my $self = {};
	bless $self, $class;

	$self->{worker} = Eldhelm::Test::Mock::Worker->new(config => $args{config});
	$self->{session} = Eldhelm::Test::Mock::Session->new($args{sessionArgs} ? %{ $args{sessionArgs} } : ());

	confess "No controller class supplied" unless $args{controller};

	$self->{controller} = Eldhelm::Util::Factory->instanceFromNotation(
		"Eldhelm::Application::Controller",
		$args{controller},
		worker     => $self->{worker},
		connection => Eldhelm::Test::Mock::Connection->new(session => $self->{session}),
		data       => {},
		$args{controllerArgs} ? %{ $args{controllerArgs} } : ()
	);

	return $self;
}

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

sub controller {
	my ($self) = @_;
	return $self->{controller};
}

sub session {
	my ($self) = @_;
	return $self->{session};
}

1;
