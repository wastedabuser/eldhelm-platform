package Eldhelm::Test::Fixture::ControllerTester;

use strict;
use threads;
use threads::shared;
use Carp;
use Eldhelm::Util::Factory;

use base qw(Eldhelm::Test::Fixture::TestBench);

sub new {
	my ($class, %args) = @_;

	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	confess "No controller class supplied" unless $args{controller};

	$self->{controller} = Eldhelm::Util::Factory->instanceFromNotation(
		"Eldhelm::Application::Controller",
		$args{controller},
		worker     => $self->{worker},
		connection => $self->{connection},
		data       => {},
		$args{controllerArgs} ? %{ $args{controllerArgs} } : ()
	);

	return $self;
}

sub controller {
	my ($self) = @_;
	return $self->{controller};
}

1;
