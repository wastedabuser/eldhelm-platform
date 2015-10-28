package Eldhelm::Util::Version;

=pod

=head1 NAME

Eldhelm::Util::Version - A utility for parsing and comparing version numbers.

=head1 SYNOPSIS

This is a static class.

=head1 Description

Parses the versions in the format C<1.0.0.0>.

All methods accept the optional C<$d> argument. 
It indicates how many chunks of the version to parse and compare. If it is 3, versions in the format C<1.0.0.0.0> will be equal to C<1.0.0>.

C<$d> defaults to 3!

=head1 METHODS

=over

=cut

use strict;

=item greaterThan($v1, $v2, $d) 1 or udef

Checks whether C<$v1> is greater than C<$v2>.

C<$v1> String - Version number;
C<$v2> String - Version number;
C<$d> Number - Optional; See the description for details;

=cut

sub greaterThan {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v1, $v2, $d) = @_;
	
	return compare($v1, $v2, $d) > 0;
}

=item lessThan($v1, $v2, $d) 1 or udef

Checks whether C<$v1> is less than C<$v2>.

C<$v1> String - Version number;
C<$v2> String - Version number;
C<$d> Number - Optional; See the description for details;

=cut

sub lessThan {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v1, $v2, $d) = @_;
	
	return compare($v1, $v2, $d) < 0;
}

=item greaterOrEqThan($v1, $v2, $d) 1 or udef

Checks whether C<$v1> is greater or equal to C<$v2>.

C<$v1> String - Version number;
C<$v2> String - Version number;
C<$d> Number - Optional; See the description for details;

=cut

sub greaterOrEqThan {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v1, $v2, $d) = @_;
	
	return compare($v1, $v2, $d) >= 0;
}

=item lessOrEqThan($v1, $v2, $d) 1 or udef

Checks whether C<$v1> is less or equal to C<$v2>.

C<$v1> String - Version number;
C<$v2> String - Version number;
C<$d> Number - Optional; See the description for details;

=cut

sub lessOrEqThan {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v1, $v2, $d) = @_;
	
	return compare($v1, $v2, $d) <= 0;
}

=item equal($v1, $v2, $d) 1 or udef

Checks whether C<$v1> is equal to C<$v2>.

C<$v1> String - Version number;
C<$v2> String - Version number;
C<$d> Number - Optional; See the description for details;

=cut

sub equal {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v1, $v2, $d) = @_;
	
	return compare($v1, $v2, $d) == 0;
}

=item compare($v1, $v2, $d) 1 or -1 or 0

Compares C<$v1> to C<$v2>.

C<$v1> String - Version number;
C<$v2> String - Version number;
C<$d> Number - Optional; See the description for details;

=cut

### UNIT TEST: 301_version_parsing.pl ###

sub compare {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v1, $v2, $d) = @_;
	$d = 3 unless $d;

	my $pv1 = parseVersion($v1, $d);
	my $pv2 = parseVersion($v2, $d);

	if ($pv1 > $pv2) {
		return 1;
	} elsif ($pv1 < $pv2) {
		return -1;
	}

	return 0;
}

=item parseVersion($v, $d) Number

Converts the version string to number.

C<$v> String - Version number;
C<$d> Number - Optional; See the description for details;

=cut

sub parseVersion {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v, $d) = @_;

	my @c = split /\./, $v;
	@c = @c[ 0 .. $d - 1 ] if $d;
	my $var = "";
	$var .= sprintf("%04d", $_) foreach @c;
	return $var;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
