package Eldhelm::Server::BaseObject;

=pod

=head1 NAME

Eldhelm::Server::BaseObject 

=head1 SYNOPSIS

This class should not be constructed directly. That's why it does not provide a constructor. You should:

	use parent 'Eldhelm::Server::BaseObject';

=head1 DESCRIPTION

A base class for all persistant objects. Provides method for thread-safe data manipulation.

=head1 METHODS

=over

=cut

use strict;

use threads;
use threads::shared;
use Eldhelm::Server::Child;
use Eldhelm::Server::Main;
use Eldhelm::Util::Factory;
use Eldhelm::Util::Tool;

=item worker() Eldhelm::Server::Child or Eldhelm::Server::Main

Returns the current thread wrapper class. The returned type depends on the thread wrapper class.

=cut

sub worker {
	my ($self) = @_;
	return Eldhelm::Server::Child->instance || Eldhelm::Server::Main->instance;
}

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

sub getRefByNotation {
	my ($self, $key) = @_;
	return ($self, $key) if $key !~ /\./;
	my @chunks = split /\./, $key;
	my $name = pop @chunks;
	return ($self, $name) unless @chunks;
	my $var = $self;
	$var = $var->{$_} ||= shared_clone({}) foreach @chunks;
	return ($var, $name);
}

=item set($key, $value) self

Sets a property value.

C<$key> String - the name of the property or it's dotted notation;
C<$value> Mixed - a value to be stored into the property;

	$self->set('a', 1);
	
	# or deeper
	$self->set('a.b', 1);

=cut

sub set {
	my ($self, $key, $value) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	if (ref($value) && !is_shared($value)) {
		$var->{$rkey} = shared_clone($value);
	} else {
		$var->{$rkey} = $value;
	}
	return $self;
}

=item setHash(%values) self

Sets multiple properties at once.

C<%values> Hash - key => value pairs of the property or their dotted notations;

	$self->setHash(
		a => 1,
		b => 1,
		
		# or deeper
		'a.b' => 2 
	);

=cut

sub setHash {
	my ($self, %values) = @_;
	lock($self);

	$self->set($_, $values{$_}) foreach keys %values;
	return $self;
}

=item get($key) self

Gets a property.

C<$key> String - the name of the property or it's dotted notation;

	my $a = $self->get('a');
	
	# or deeper
	my $ab = $self->get('a.b');

=cut

sub get {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return $var->{$rkey};
}

=item getList(@list) Array

Returns a list of properties.

C<@list> Array - The list of properties to be returned;

	my ($a, $b) = 
		$self->getList('a', 'b');

=cut

sub getList {
	my ($self, @list) = @_;
	lock($self);

	return map { $self->get($_) } @list;
}

=item getPureList(@list) Array

Returns a list of properties containing array as a single list.

C<@list> Array - The list of properties to be returned;

	$self->set('a', [1, 2]);
	$self->set('b', [3, 4]);
	
	my @values = 
		$self->getPureList('a', 'b');
		
	# @values is
	# (1, 2, 3, 4)

=cut

sub getPureList {
	my ($self, @list) = @_;
	lock($self);

	return map { ref $self->{$_} eq 'ARRAY' ? @{ $self->{$_} } : $self->{$_} || () } @list;
}

=item getHash(@list) Hash

Returns a list of properties as key => value paris.

C<@list> Array - The list of properties to be returned;

	my %values = 
		$self->getHash('a', 'b');
		
	# use them as 
	# $value{a} and $value{b};

=cut

sub getHash {
	my ($self, @list) = @_;
	lock($self);

	return map { +$_ => $self->get($_) } @list;
}

=item getDefinedHash(@list) Hash

Returns a list of properties as key => value paris.

C<@list> Array - The list of properties to be returned;

	$self->set('a.prop', 1);
	$self->set('b.prop', 2);
	
	my %values = 
		$self->getDefinedHash('a.prop', 'b.prop', 'c.prop');
		
	# returns the first two but not the third
	# as it is not defined
	# use them like this:
	# $value{'a.prop'} and $value{'b.prop'};

=cut

sub getDefinedAsHash {
	my ($self, @list) = @_;
	lock($self);

	return map { +$_->[0] => $_->[1] } grep { defined $_->[1] } map { [ $_, $self->get($_) ] } @list;
}

=item remove($key) Mixed

Removes a property and returns its value.

C<$key> String - the name of the property or it's dotted notation;

=cut

sub remove {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return delete $var->{$rkey};
}

=item removeList(@list) Array

Removes a list of properties and returns a list of their values.

C<@list> Array - The list of properties to be removed;

=cut

sub removeList {
	my ($self, @list) = @_;
	lock($self);

	my @deleted;
	push @deleted, delete $self->{$_} foreach @list;

	return @deleted;
}

=item inc($key, $amount) Number

Increments a property and returns the new value.

C<$key> String - The name of the property or it's dotted notation;
C<$amount> Number - Optional; The amount to be added; Defaults to 1;

=cut

sub inc {
	my ($self, $key, $amount) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return $var->{$rkey} += $amount || 1;
}

=item dec($key, $amount) Number

Decrements a property and returns the new value.

C<$key> String - The name of the property or it's dotted notation;
C<$amount> Number - Optional; The amount to be added; Defaults to 1;

=cut

sub dec {
	my ($self, $key, $amount) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return $var->{$rkey} -= $amount || 1;
}

=item pushItem($key, $item)

Finds an array property by its name and pushes a value into the array.

C<$key> String - The name of the property or it's dotted notation;
C<$item> Mixed - The value to be pushed;

=cut

sub pushItem {
	my ($self, $key, $item) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return unless ref $var;

	$var->{$rkey} ||= shared_clone([]);
	if (ref($item) && !is_shared($item)) {
		$item = shared_clone($item);
	}
	return push @{ $var->{$rkey} }, $item;
}

=item grepArrayref($key, $callback, @options) ArrayRef

Filters an array property in-place.

C<$key> String - The name of the property or it's dotted notation;
C<$callback> FunctionRef - The callback to be applied on every item;
C<@options> Optional; Additionl arguments to the callback function;

	$self->grepArrayref('a', sub {
		my ($item, $more) = @_;
		
	}, $more);

=cut

sub grepArrayref {
	my ($self, $key, $fn, @options) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return unless ref $var && ref $var->{$rkey} eq 'ARRAY';

	my $list = $var->{$rkey};
	@$list = grep { $fn->($_, @options) } @$list;

	return $list;
}

=item clearArrayref($key) self

Clears an array property so it contaigns no elements.

C<$key> String - The name of the property or it's dotted notation;

=cut

sub clearArrayref {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return $self unless ref $var;

	if (ref $var->{$rkey} eq 'ARRAY') {
		@{ $var->{$rkey} } = ();
	} else {
		$var->{$rkey} = shared_clone([]);
	}

	return $self;
}

=item scalarArrayref($key) Number

Returns the number of elements in an array property.

C<$key> String - The name of the property or it's dotted notation;

=cut

sub scalarArrayref {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return unless ref $var && ref $var->{$rkey} eq 'ARRAY';

	return scalar @{ $var->{$rkey} };
}

=item getHashrefHash($key) Hash

Returns a propety containing a HashRef as Hash.

C<$key> String - The name of the property or it's dotted notation;

=cut

sub getHashrefHash {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	my $ref = $var->{$rkey};
	return () if ref $ref ne 'HASH';

	return %$ref;
}

=item getHashrefKeys($key) Array

Returns list of keys of a propety containing a HashRef.

C<$key> String - The name of the property or it's dotted notation;

=cut

sub getHashrefKeys {
	my ($self, $key) = @_;
	lock($self);

	return keys(%$self) unless $key;

	my ($var, $rkey) = $self->getRefByNotation($key);
	my $ref = $var->{$rkey};
	return () if ref $ref ne 'HASH';

	return keys %$ref;
}

=item getHashrefValues($key) Array

Returns list of values of a propety containing a HashRef.

C<$key> String - The name of the property or it's dotted notation;

=cut

sub getHashrefValues {
	my ($self, $key, $keysList) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	my $ref = $var->{$rkey};
	return () if ref $ref ne 'HASH';

	if (ref $keysList eq 'ARRAY') {
		return map { $ref->{$_} } grep { exists $ref->{$_} } @$keysList;
	}

	return values %$ref;
}

=item clone($key) Mixed

Returns a deep clone of the structure contained in a property.

C<$key> String - The name of the property or it's dotted notation;

=cut

sub clone {
	my ($self, $key) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	my $ref = $var->{$rkey};

	return Eldhelm::Util::Tool->cloneStructure($ref);
}

=item doFn($callback, @options) Mixed

Applies a callback over the current object. This is usefult to create a theread-safe scope direct data manipulation.

C<$callback> FunctionRef - The callback to be applied on every item;
C<@options> Optional; Additionl arguments to the callback function;

	# DON'T !!!
	# you will lock the server
	$self->{a} = 1;
	
	# instead do
	$self->doFn(sub {
		my ($self) = @_;
		
		$self->{a} = 1;
		
	});

Note that this is equvalent to:

	$self->set('a', 1);

So use this construct only when you need to do something complicated ...

Please note that you should never interact with other persistant objects inside the callback scope!
	
	# let's say $a and $b
	# are persistant objects
	
	$a->doFn(sub {
		my ($self) = @_;
		
		# OK
		$a->{prop} = 1;
		$self->{prop} = 1;
		
		# OK, but dumm
		$a->set('prop', 1);
		
		# DON'T !!!
		$b->set('prop', 1);
		# never menthion $b inside
		# this scope
		
	});
	
	# Doing it here
	# is of course OK
	$b->set('prop', 1);

=cut

sub doFn {
	my ($self, $fn, @options) = @_;
	lock($self);

	return $fn->($self, @options);
}

=item setWhenFalse($key, $value) Mixed

Acts as set when the property given by $key is false (0, undef or ''). If not the property value is returned.

C<$key> String - The name of the property or it's dotted notation;
C<$value> Mixed - Optional; The property to be set; Defaults to 1;

	my $r = $self->setWhenFalse('a', 1);
	# $r is undef
	# then if we call it again
	$r = $self->setWhenFalse('a', 2);
	# $r is 1

=cut

sub setWhenFalse {
	my ($self, $key, $value) = @_;
	lock($self);

	my ($var, $rkey) = $self->getRefByNotation($key);
	return $var->{$rkey} if $var->{$rkey};

	$value ||= 1;
	if (ref($value) && !is_shared($value)) {
		$var->{$rkey} = shared_clone($value);
	} else {
		$var->{$rkey} = $value;
	}

	return;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
