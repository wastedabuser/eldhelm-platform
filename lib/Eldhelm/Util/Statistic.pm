package Eldhelm::Util::Statistic;

use strict;

sub aggregateInGroups {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data, $groups) = @_;
	my @result;
	foreach my $s (@$groups) {
		my $sum = 0;
		$sum += $_->{cnt} foreach grep { $_->{val} > $s->[0] && $_->{val} <= $s->[1] } @$data;
		push @result, [ $s->[2], $sum ];
	}
	return \@result;

}

sub calculateAverage {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	my ($sumVal, $sumCnt) = (0, 0);
	foreach my $s (@$data) {
		$sumVal += $s->{val};
		$sumCnt += $s->{cnt};
	}
	return $sumVal / $sumCnt;
}

1;
