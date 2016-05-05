package Eldhelm::Server::BaseObject;

=pod

=head1 NAME

Eldhelm::Server::BaseObject 

=head1 SYNOPSIS

This class should not be constructed directly. That's why it does not provide a constructor. You should:

	use parent 'Eldhelm::Server::BaseObject';

=head1 DESCRIPTION

A base class for all persistant objects. Please see L<Eldhelm::Util::ThreadsafeData>.
Eldhelm::Server::BaseObject will delegate it's threadsafe method calls to L<Eldhelm::Util::ThreadsafeData>.

=head1 METHODS

=over

=cut

use strict;

use Carp;
use threads;
use threads::shared;
use Eldhelm::Server::Child;
use Eldhelm::Server::Main;
use Eldhelm::Util::Factory;
use Eldhelm::Util::ThreadsafeData;
use Eldhelm::Basic::DataObject;

=item worker() Eldhelm::Server::Child or Eldhelm::Server::Main

Returns the current thread wrapper class. The returned type depends on the thread wrapper class.

=cut

sub worker {
	my ($self) = @_;
	return Eldhelm::Server::Child->instance || Eldhelm::Server::Main->instance;
}

sub AUTOLOAD {
	my $self = shift;

	my $method = our $AUTOLOAD;
	$method =~ s/^.*:://;

	confess "Can not call method '$method' via autoload: not a blessed reference" unless ref $self;

	if ($self->can($method)) {
		$self->$method(@_);
		return;
	}

	my $fn = Eldhelm::Util::ThreadsafeData->can($method);
	confess "Can not call method '$method' via autoload: '$method' not defined" unless $fn;

	return $fn->($self, $self, $self, @_);
}

sub DESTROY { }

sub compose {
	my ($self, $data, $options) = @_;
	my $composer = $self->get('composer');
	if ($composer) {
		Eldhelm::Util::Factory->usePackage($composer);
		my $composed;
		eval {
			$composed = $composer->compose($data, $options);
			1;
		} or do {
			$self->worker->error("Error while encoding data: $@") if $@;
		};
		return $composed;
	} else {
		return $data;
	}
}

=item dataObject($key) Eldhelm::Basic::DataObject

Creates an object holding a reference to the one discovered from the key.

C<$key> String - the name of the property or it's dotted notation;

	$object->dataObject('my.very.very.deep.reference')->get('property');

=cut

sub dataObject {
	my ($self, $key) = @_;
	lock($self);
	my ($var, $rkey) = Eldhelm::Util::ThreadsafeData::getRefByNotation($self, $key);
	$var = $var->{$rkey} ||= shared_clone({});
	return Eldhelm::Basic::DataObject->new(
		baseRef => $self,
		dataRef => $var
	);
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
