package Eldhelm::Basic::Model;

use strict;
use Eldhelm::Server::Child;
use Eldhelm::Database::Pool;
use Data::Dumper;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {
		%args,
		worker => Eldhelm::Server::Child->instance,
		dbPool => Eldhelm::Database::Pool->new,
	};
	bless $self, $class;

	return $self;
}

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

sub getModel {
	my ($self, $model, $args) = @_;
	$args ||= {};
	return Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Application::Model", $model, %$args);
}

sub instanceOf {
	my ($self, $model) = @_;
	return Eldhelm::Util::Factory->instanceOf($self, "Eldhelm::Application::Model", $model);
}

sub getDb {
	my ($self) = @_;
	confess "No dbPool" if !$self->{dbPool};
	return $self->{dbPool}->getDb;
}

1;
