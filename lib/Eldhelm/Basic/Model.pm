package Eldhelm::Basic::Model;

=pod

=head1 NAME

Eldhelm::Basic::Model - The base of all model classes.

=head1 SYNOPSIS

This class should not be used directly, please see it's child classes.
Inheriting this class makes sense only if you are creating a completly new model type.

Please see: L<< Eldhelm::Basic::Controller->getModel >>

=head1 DESCRIPTION

This class provides the basic functionallity need for all models.

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Server::Child;
use Eldhelm::Database::Pool;
use Data::Dumper;
use Carp;

=item new(%args)

Constructs a new object.

C<%args> Hash - Contructor argumets;

=cut

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

=item worker() Eldhelm::Server::Worker

Returns the current worker thread wrapper class.

=cut

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

=item getModel($model, $args) Eldhelm::Application::Model

Returns a model object by name.

C<$model> String - a dotted notation poiting to a class in the C<Eldhelm::Application::Model> namespace;
C<$args> HashRef - arguments passed to the model constructor;

=cut

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

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
