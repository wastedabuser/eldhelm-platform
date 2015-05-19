package Eldhelm::Util::Factory;

use strict;
use Carp;

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

sub parseNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($name) = @_;
	$name =~ s/_(.)/uc($1)/ge;
	my @nm = map { ucfirst $_ } split /[^a-z0-9]+/i, $name;
	return @nm;
}

sub packageFromNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ns, $name) = @_;
	return join("::", $ns || (), parseNotation($name));
}

sub pathFromNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ns, $name) = @_;
	return join("/", $ns || (), parseNotation($name));
}

sub instanceFromNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ns, $name, %args) = @_;
	my $inst;
	eval { $inst = instance(packageFromNotation($ns, $name), %args) };
	confess $@ if $@;
	return $inst;
}

sub instanceOf {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref, $ns, $name) = @_;
	return $ref->isa(packageFromNotation($ns, $name));
}

1;
