package Eldhelm::Util::Math;

use strict;

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

1;