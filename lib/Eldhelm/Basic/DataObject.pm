package Eldhelm::Basic::DataObject;

=pod

=head1 NAME

Eldhelm::Basic::DataObject - A data accessor object.

=head1 SYNOPSIS

	# $object is Eldhelm::Server::BaseObject
	my $dataObj = $object->dataObject('my.very.very.deep.reference');
	
	# $dataObj is Eldhelm::Basic::DataObject
	# do some work with it like:
	$dataObj->get('property');
	$dataObj->set('other-property', 1);

=head1 DESCRIPTION

Threadsafe access of data. In general you should not construct this object yourself, please see L<< Eldhelm::Server::BaseObject->dataObject >>.
Eldhelm::Basic::DataObject will delegate it's threadsafe method calls to L<Eldhelm::Util::ThreadsafeData>.

=head1 METHODS

=over

=cut

use strict;

use Carp;
use Data::Dumper;
use Eldhelm::Util::ThreadsafeData;

=item new(%args)

Constructs a new object.

C<%args> Hash - Contructor argumets;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {
		%args
	};
	bless $self, $class;
	return $self;
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

	return $fn->($self, $self->{baseRef}, $self->{dataRef}, @_);
}

sub DESTROY { }

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;