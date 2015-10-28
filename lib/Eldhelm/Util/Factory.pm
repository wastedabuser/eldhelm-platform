package Eldhelm::Util::Factory;

=pod

=head1 NAME

Eldhelm::Util::Factory - A utility class for constructing objects.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;
use Carp;

=item getAbsoluteClassPath($name, $prefix, @paths) String or undef

Searches for class C<$name> prefixed by C<$prefix> in C<@INC> and the additional C<@paths>.
When a file is found in one of the locations its location is cached.

C<$name> String - The name of the class;
C<$prefix> String - Optional; A prefix or a String to be added before the class name;
C<@paths> Array - Optional; Additional paths to be searched;

=cut

my %absolutePathCache;

sub getAbsoluteClassPath {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($name, $prefix, @paths) = @_;
	return $absolutePathCache{$name} if $absolutePathCache{$name};
	
	if ($prefix) {
		push @paths, map { "$_$prefix" } @INC;
	} else {
		push @paths, @INC;
	}
	
	foreach (@paths) {
		my $pt = "$_/$name";
		return $absolutePathCache{$name} = $pt if -f $pt;
	}
	
	return undef;
}

=item instance($name, %args) Object

Constructs an object from a class name in the C<Package::Name> format.

C<$name> String - The name of the class.
C<%args> Hash - constructor argments.

=cut

sub instance {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($nm, %args) = @_;
	usePackage($nm);
	my $inst;
	eval { $inst = $nm->new(%args) };
	confess "Error while creaing instance '$nm': $@"
		if $@;
	return $inst;
}

sub usePackage {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($nm) = @_;
	confess "Can not create instance without a name" if !$nm;
	eval "use $nm";
	confess "Can not use package '$nm': $@"
		if $@;
}

=item instance($name, $ref) Object

Blesses the C<$ref> to the class with C<$name>.

C<$name> String - The class name;
C<$ref> HashRef - The object to be blessed;

=cut

sub instanceFromScalar {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($nm, $ref) = @_;
	usePackage($nm);
	my $inst;
	eval { $inst = bless $ref, $nm };
	confess "Error while creaing instance '$nm': $@"
		if $@;
	return $inst;
}

=item parseNotation($name) Array

Converts a dotted notation to a class name chunks. C<myPackage.myClass> will become C<('MyPackage','MyClass')>.

C<$name> String - A dotted notation;

=cut

sub parseNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($name) = @_;
	$name =~ s/_(.)/uc($1)/ge;
	my @nm = map { ucfirst $_ } split /[^a-z0-9]+/i, $name;
	return @nm;
}

=item packageFromNotation($ns, $name) String

Converts a dotted notation to a class name. C<myPackage.myClass> will become C<'MyPackage::MyClass'>, but prefixes it with the provided namespace.

C<$ns> String - The namespace to prefix the class name;
C<$name> String - A dotted notation;

=cut

sub packageFromNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ns, $name) = @_;
	return join("::", $ns || (), parseNotation($name));
}

=item pathFromNotation($ns, $name) String

Converts a dotted notation to a file path. C<myPackage.myClass> will become C<'MyPackage/MyClass'>, but prefixes it with the provided namespace.

C<$ns> String - The namespace to prefix the class name;
C<$name> String - A dotted notation;

=cut

sub pathFromNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ns, $name) = @_;
	return join("/", $ns || (), parseNotation($name));
}

=item instanceFromNotation($ns, $name, %args) String

Creates an object from a dotted notation. C<myPackage.myClass> will become the object C<MyPackage::MyClass>.

C<$ns> String - The namespace to prefix the class name;
C<$name> String - A dotted notation;
C<%args> Hash - Optional; Constructor arguments;

=cut

sub instanceFromNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ns, $name, %args) = @_;
	my $inst;
	eval { $inst = instance(packageFromNotation($ns, $name), %args) };
	confess $@ if $@;
	return $inst;
}

=item instanceOf($ref, $ns, $name) 1 or undef

Checks whether the object instance C<$ref> is of the C<$name> represented in dotted notation from the C<$ns> namespace.

C<$ref> Object - An object instance to be checked;
C<$ns> String - The namespace to prefix the class name;
C<$name> String - A dotted notation;

=cut

sub instanceOf {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref, $ns, $name) = @_;
	return $ref->isa(packageFromNotation($ns, $name));
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
