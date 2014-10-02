package Eldhelm::Util::Version;

use strict;

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

sub parseVersion {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($v, $d) = @_;

	my @c = split /\./, $v;
	@c = @c[ 0 .. $d - 1 ];
	$_ *= 1000 foreach @c;
	my $var = "";
	$var .= $_ foreach @c;
	return $var;
}

1;
