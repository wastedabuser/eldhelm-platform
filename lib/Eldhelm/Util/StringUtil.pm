package Eldhelm::Util::StringUtil;

use strict;

sub randomString {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($len, $chars) = @_;
	my @chars = @{ $chars || [ 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_' ] };
	return join "", map { $chars[ rand scalar @chars ] } 1 .. $len;
}

sub keyCodeFromString {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($str) = @_;
	$str = lc($str);
	$str =~ s/\s/_/g;
	$str =~ s/[^a-z0-9_]//g;
	return $str;

}

1;