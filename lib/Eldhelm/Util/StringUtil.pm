package Eldhelm::Util::StringUtil;

=pod

=head1 NAME

Eldhelm::Util::StringUtil - A utility for string manipulation.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;

=item randomString($len, $chars) String

Generates a random string.

C<$len> Number - The length of the string to be genrated;
C<$chars> ArrayRef - Optional; The charcters to be used; Defaults to C<[ 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_' ]>;

=cut

sub randomString {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($len, $chars) = @_;
	my @chars = @{ $chars || [ 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_' ] };
	return join "", map { $chars[ rand scalar @chars ] } 1 .. $len;
}

=item keyCodeFromString

Coverts any string to code containing only characters in a-z, 0-9 and _. Useful for URLs and JSON keys.

C<$str> String - The String to be converted;

=cut

sub keyCodeFromString {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($str) = @_;
	$str = lc($str);
	$str =~ s/\s/_/g;
	$str =~ s/[^a-z0-9_]//g;
	return $str;

}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;