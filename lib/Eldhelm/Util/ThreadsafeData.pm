package Eldhelm::Util::ThreadsafeData;

=pod

=head1 NAME

Eldhelm::Basic::ThreadsafeData - A data accessor object.

=head1 SYNOPSIS

	# $object is Eldhelm::Server::BaseObject
	my $dataObj = $object->dataObject('my.very.very.deep.reference');
	
	# $dataObj is Eldhelm::Basic::DataObject
	# do some work with it like:
	$dataObj->get('property');
	$dataObj->set('other-property', 1);

=head1 DESCRIPTION

Threadsafe access of data. You should not use this class directly. Please see L<Eldhelm::Server::BaseObject> and L<Eldhelm::Basic::DataObject>.

=head1 METHODS

=over

=cut

use strict;

use Carp;
use threads;
use threads::shared;
use Data::Dumper;
use Eldhelm::Util::Tool;

=item getRefByNotation($dataRef, $key) Array

Searches for an object within a reference by dotted notation

C<$dataRef> HashRef - A data structure;
C<$key> String - the name of the property or it's dotted notation;

=cut

sub getRefByNotation {
	my ($dataRef, $key) = @_;
	return ($dataRef, $key) if index($key, '.') < 0;
	my @chunks = split /\./, $key;
	my $name = pop @chunks;
	return ($dataRef, $name) unless @chunks;
	my $var = $dataRef;
	$var = $var->{$_} ||= shared_clone({}) foreach @chunks;
	return ($var, $name);
}

=item set($self, $baseRef, $dataRef, $key, $value) self

Sets a property value.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - the name of the property or it's dotted notation;
C<$value> Mixed - a value to be stored into the property;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	$self->set('a', 1);
	
	# or deeper
	$self->set('a.b', 1);

=cut

sub set {
	my ($self, $baseRef, $dataRef, $key, $value) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	if (ref($value) && !is_shared($value)) {
		$var->{$rkey} = shared_clone($value);
	} else {
		$var->{$rkey} = $value;
	}
	return $self;
}

=item setWhenFalse($self, $baseRef, $dataRef, $key, $value) Mixed

Acts as set when the property given by $key is false (0, undef or ''). If not the property value is returned.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;
C<$value> Mixed - Optional; The property to be set; Defaults to 1;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	my $r = $self->setWhenFalse('a', 1);
	# $r is undef
	# then if we call it again
	$r = $self->setWhenFalse('a', 2);
	# $r is 1

=cut

sub setWhenFalse {
	my ($self, $baseRef, $dataRef, $key, $value) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return $var->{$rkey} if $var->{$rkey};

	$value ||= 1;
	if (ref($value) && !is_shared($value)) {
		$var->{$rkey} = shared_clone($value);
	} else {
		$var->{$rkey} = $value;
	}

	return;
}

=item setHash($self, $baseRef, $dataRef, %values) self

Sets multiple properties at once.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<%values> Hash - key => value pairs of the property or their dotted notations;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	$self->setHash(
		a => 1,
		b => 1,
		
		# or deeper
		'a.b' => 2 
	);

=cut

sub setHash {
	my ($self, $baseRef, $dataRef, %values) = @_;
	lock($baseRef);

	set($self, $baseRef, $dataRef, $_, $values{$_}) foreach keys %values;
	return $self;
}

=item get($self, $baseRef, $dataRef, $key) self

Gets a property.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - the name of the property or it's dotted notation;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	my $a = $self->get('a');
	
	# or deeper
	my $ab = $self->get('a.b');

=cut

sub get {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return $var->{$rkey};
}

=item isDefined($self, $baseRef, $dataRef, $key) self

Checks whether a proeprty is defined

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - the name of the property or it's dotted notation;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	my $a = $self->isDefined('a');
	
	# or deeper
	my $ab = $self->isDefined('a.b');

=cut

sub isDefined {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return defined $var->{$rkey};
}

=item getList($self, $baseRef, $dataRef, @list) Array

Returns a list of properties.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<@list> Array - The list of properties to be returned;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	my ($a, $b) = 
		$self->getList('a', 'b');

=cut

sub getList {
	my ($self, $baseRef, $dataRef, @list) = @_;
	lock($baseRef);

	return map { get($self, $baseRef, $dataRef, $_) } @list;
}

=item getPureList($self, $baseRef, $dataRef, @list) Array

Returns a list of properties containing array as a single list.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<@list> Array - The list of properties to be returned;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	$self->set('a', [1, 2]);
	$self->set('b', [3, 4]);
	
	my @values = 
		$self->getPureList('a', 'b');
		
	# @values is
	# (1, 2, 3, 4)

=cut

sub getPureList {
	my ($self, $baseRef, $dataRef, @list) = @_;
	lock($baseRef);

	return map { ref $baseRef->{$_} eq 'ARRAY' ? @{ $baseRef->{$_} } : $baseRef->{$_} || () } @list;
}

=item getHash($self, $baseRef, $dataRef, @list) Hash

Returns a list of properties as key => value paris.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<@list> Array - The list of properties to be returned;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	my %values = 
		$self->getHash('a', 'b');
		
	# use them as 
	# $value{a} and $value{b};

=cut

sub getHash {
	my ($self, $baseRef, $dataRef, @list) = @_;
	lock($baseRef);

	return map { +$_ => $self->get($_) } @list;
}

=item getDefinedHash($self, $baseRef, $dataRef, @list) Hash

Returns a list of properties as key => value paris.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<@list> Array - The list of properties to be returned;

	# let's say
	# $self is Eldhelm::Basic::DataObject
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
	my ($self, $baseRef, $dataRef, @list) = @_;
	lock($baseRef);

	return
		map { +$_->[0] => $_->[1] } grep { defined $_->[1] } map { [ $_, get($self, $baseRef, $dataRef, $_) ] } @list;
}

=item remove($self, $baseRef, $dataRef, $key) Mixed

Removes a property and returns its value.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - the name of the property or it's dotted notation;

=cut

sub remove {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return delete $var->{$rkey};
}

=item removeList($self, $baseRef, $dataRef, @list) Array

Removes a list of properties and returns a list of their values.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<@list> Array - The list of properties to be removed;

=cut

sub removeList {
	my ($self, $baseRef, $dataRef, @list) = @_;
	lock($baseRef);

	my @deleted;
	push @deleted, delete $baseRef->{$_} foreach @list;

	return @deleted;
}

=item inc($self, $baseRef, $dataRef, $key, $amount) Number

Increments a property and returns the new value.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;
C<$amount> Number - Optional; The amount to be added; Defaults to 1;

=cut

sub inc {
	my ($self, $baseRef, $dataRef, $key, $amount) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return $var->{$rkey} += $amount || 1;
}

=item dec($self, $baseRef, $dataRef, $key, $amount) Number

Decrements a property and returns the new value.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;
C<$amount> Number - Optional; The amount to be added; Defaults to 1;

=cut

sub dec {
	my ($self, $baseRef, $dataRef, $key, $amount) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return $var->{$rkey} -= $amount || 1;
}

=item pushItem($self, $baseRef, $dataRef, $key, @items)

Finds an array property by its name and pushes items into the array.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;
C<@items> Array - Items to be pushed;

=cut

sub pushItem {
	my ($self, $baseRef, $dataRef, $key, @items) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return unless ref $var;

	$var->{$rkey} ||= shared_clone([]);
	foreach my $item (@items) {
		if (ref($item) && !is_shared($item)) {
			$item = shared_clone($item);
		}
		push @{ $var->{$rkey} }, $item;
	}

	return $self;
}

=item shiftItem($self, $baseRef, $dataRef, $key)

Finds an array property by its name and shifts a value from the array.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;

=cut

sub shiftItem {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return unless ref $var;

	my $arr = $var->{$rkey};
	return unless $arr;

	return shift @$arr;
}

=item grepArrayref($self, $baseRef, $dataRef, $key, $callback, @options) ArrayRef

Filters an array property in-place.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;
C<$callback> FunctionRef - The callback to be applied on every item;
C<@options> Optional; Additionl arguments to the callback function;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	$self->grepArrayref('a', sub {
		my ($item, $more) = @_;
		
	}, $more);

=cut

sub grepArrayref {
	my ($self, $baseRef, $dataRef, $key, $fn, @options) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return unless ref $var && ref $var->{$rkey} eq 'ARRAY';

	my $list = $var->{$rkey};
	@$list = grep { $fn->($_, @options) } @$list;

	return $list;
}

=item clearArrayref($self, $baseRef, $dataRef, $key) self

Clears an array property so it contaigns no elements.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;

=cut

sub clearArrayref {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return $self unless ref $var;

	if (ref $var->{$rkey} eq 'ARRAY') {
		@{ $var->{$rkey} } = ();
	} else {
		$var->{$rkey} = shared_clone([]);
	}

	return $self;
}

=item scalarArrayref($self, $baseRef, $dataRef, $key) Number

Returns the number of elements in an array property.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;

=cut

sub scalarArrayref {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	return 0 unless ref $var && ref $var->{$rkey} eq 'ARRAY';

	return scalar @{ $var->{$rkey} };
}

=item getHashrefHash($self, $baseRef, $dataRef, $key) Hash

Returns a propety containing a HashRef as Hash.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;

=cut

sub getHashrefHash {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	my $ref = $var->{$rkey};
	return () if ref $ref ne 'HASH';

	return %$ref;
}

=item getHashrefKeys($self, $baseRef, $dataRef, $key) Array

Returns list of keys of a propety containing a HashRef.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;

=cut

sub getHashrefKeys {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	return keys(%$self) unless $key;

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	my $ref = $var->{$rkey};
	return () if ref $ref ne 'HASH';

	return keys %$ref;
}

=item getHashrefValues($self, $baseRef, $dataRef, $key) Array

Returns list of values of a propety containing a HashRef.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;

=cut

sub getHashrefValues {
	my ($self, $baseRef, $dataRef, $key, $keysList) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	my $ref = $var->{$rkey};
	return () if ref $ref ne 'HASH';

	if (ref $keysList eq 'ARRAY') {
		return map { $ref->{$_} } grep { exists $ref->{$_} } @$keysList;
	}

	return values %$ref;
}

=item clone($self, $baseRef, $dataRef, $key) Mixed

Returns a deep clone of the structure contained in a property.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$key> String - The name of the property or it's dotted notation;

=cut

sub clone {
	my ($self, $baseRef, $dataRef, $key) = @_;
	lock($baseRef);

	my ($var, $rkey) = getRefByNotation($dataRef, $key);
	my $ref = $var->{$rkey};

	return Eldhelm::Util::Tool->cloneStructure($ref);
}

=item lockedScope($self, $baseRef, $dataRef, $callback, @options) Mixed

Applies a callback over the current object. This is usefult to create a theread-safe scope for direct data manipulation.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$callback> FunctionRef - The callback to be applied on every item;
C<@options> Optional; Additionl arguments to the callback function;
	
	# let's say
	# $self is Eldhelm::Basic::DataObject
	
	# DON'T !!!
	# you will mostliekly create a deadlock situation
	$self->{a} = 1;
	
	# instead do
	$self->lockedScope(sub {
		my ($self) = @_;
		
		$self->{a} = 1;
		
	});

Note that this is equvalent to:

	$self->set('a', 1);

So use this construct only when you need to do something complicated ...

Please note that you should never interact with other persistant objects inside the callback scope!
	
	# let's say 
	# $self is Eldhelm::Basic::DataObject
	# $a and $b are persistant objects
	
	$a->lockedScope(sub {
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

sub lockedScope {
	my ($self, $baseRef, $dataRef, $fn, @options) = @_;
	lock($baseRef);

	return $fn->($baseRef, @options);
}

=item semaphoreScope($self, $baseRef, $dataRef, $semaName, $callback, @options) Mixed

Applies a callback over the current object. This is usefult to create a scope which will automatically handle a semaphore variable. While the scope is executing the semaphore will be raised.

C<$self> The caller object
C<$baseRef> HashRef - A base data structure which will hold the advisory lock;
C<$dataRef> HashRef - A data structure;
C<$semaName> String - The name of the semaphore;
C<$callback> FunctionRef - The callback to be applied on every item;
C<@options> Optional; Additionl arguments to the callback function;

	# let's say
	# $self is Eldhelm::Basic::DataObject
	# multiple threads are excuting
	# the same code
	
	if ($self->hasSemaphore('my-semaphore')) {
		# handle semaphore
		
	} else {
		# two threads will never 
		# execute the following block 
		# in the same time
		$self->semaphoreScope(
			'my-semaphore', 
			sub {
				my ($self) = @_;
				
				return unless $self->get('var1');
				# logic here
				
				return unless $self->get('var2');
				# logic here
				
				$self->set('var3', 1);
			}
		);
	}
	
=cut

sub semaphoreScope {
	my ($self, $baseRef, $dataRef, $semaName, $fn, @options) = @_;
	my $semaphoreName = "_semaphore-${semaName}_";
	$self->set($semaphoreName, 1);
	my $result = $fn->($baseRef, @options);
	$self->remove($semaphoreName);
	return $result;
}

=item hasSemaphore() 1 or undef

Checks whether a spemaphore flag has been risen. Please see C<semaphoreScope> method for an exmaple.

C<$self> The caller object
C<$semaName> String - The name of the semaphore;

=cut

sub hasSemaphore {
	my ($self, $semaName) = @_;
	my $semaphoreName = "_semaphore-${semaName}_";

	lock($self);
	return $self->{$semaphoreName};
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
