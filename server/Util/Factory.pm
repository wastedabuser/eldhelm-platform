package Eldhelm::Util::Factory;

use strict;
use Carp;

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
	my ($ns, $name) = @_;
	$name =~ s/_(.)/uc($1)/ge;
	my @nm = map { ucfirst $_ } split /[^a-z0-9]+/i, $name;
	return join("::", $ns || (), @nm);
}

sub instanceFromNotation {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ns, $name, %args) = @_;
	my $inst;
	eval { $inst = instance(parseNotation($ns, $name), %args) };
	confess $@ if $@;
	return $inst;
}

sub instanceOf {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref, $ns, $name) = @_;
	return $ref->isa(parseNotation($ns, $name));
}

1;
