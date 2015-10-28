package Eldhelm::Util::Math;

=pod

=head1 NAME

Eldhelm::Util::Math - A utility for mathematical functions.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;

=item max($list, $key) Number

Searches for the maximum number in an ArrayRef containing HashRefs.

C<$list> ArrayRef - The ArrayRef to be serached.
C<$key> Mixed - The property holding the number.

	Eldhelm::Util::Math->max([
		{ a => 1 },
		{ a => 3 },
		{ a => 2 },
	], 'a');
	# returns 3

	Eldhelm::Util::Math->max([
		{ a => { b => 2 } },
		{ a => { b => 1 } },
		{ a => { b => 3 } },
	], ['a', 'b']);
	# returns 3

=cut

sub max {
	shift @_ if $_[0] eq __PACKAGE__;
    my ($list, $key) = @_;
	my @keys = ref $key eq "ARRAY" ? @$key : ($key);
	my $max = "-inf";
    foreach my $ret (@$list) {
		$ret = $ret->{$_} foreach @keys;
        $max = $ret if $ret > $max;
    }
    return $max;
}

=item min($list, $key) Number

Searches for the minimum number in an ArrayRef containing HashRefs.

C<$list> ArrayRef - The ArrayRef to be serached.
C<$key> Mixed - The property holding the number.

	Eldhelm::Util::Math->min([
		{ a => 1 },
		{ a => 3 },
		{ a => 2 },
	], 'a');
	# returns 1

	Eldhelm::Util::Math->max([
		{ a => { b => 2 } },
		{ a => { b => 1 } },
		{ a => { b => 3 } },
	], ['a', 'b']);
	# returns 1

=cut

sub min {
	shift @_ if $_[0] eq __PACKAGE__;
    my ($list, $key) = @_;
	my @keys = ref $key eq "ARRAY" ? @$key : ($key);
	my $min = "+inf";
    foreach my $ret (@$list) {
		$ret = $ret->{$_} foreach @keys;
        $min = $ret if $ret < $min;
    }
    return $min;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;