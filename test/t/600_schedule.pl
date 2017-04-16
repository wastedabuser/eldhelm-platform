use strict;
use lib '../lib';
use lib '../../lib';
use Test::More 'no_plan';

use threads;
use threads::shared;
use Data::Dumper;
use Eldhelm::Util::Factory;
use Date::Calc qw(Date_to_Time Today_and_Now Time_to_Date Day_of_Week);

my $schedule = Eldhelm::Util::Factory->instanceFromScalar('Eldhelm::Server::Schedule', shared_clone({}));

sub now { Date_to_Time(Today_and_Now()) };

diag('second interval format');
my ($time, $interval, $priority) = $schedule->readTime('12s');
is($time, now());
is($interval->[0],0);
is($interval->[5],12);
my $delta = 12;
is($time, $schedule->calcNextTime($time, $interval) - $delta);

diag('minute interval format');
($time, $interval, $priority) = $schedule->readTime('18m');
is($time, now());
is($interval->[0],0);
is($interval->[4],18);
$delta = 18 * 60;
is($time, $schedule->calcNextTime($time, $interval) - $delta);

diag('hour interval format');
($time, $interval, $priority) = $schedule->readTime('11h');
is($time, now());
is($interval->[0],0);
is($interval->[3],11);
$delta = 11 * 60 * 60;
is($time, $schedule->calcNextTime($time, $interval) - $delta);

diag('day interval format');
($time, $interval, $priority) = $schedule->readTime('14d');
is($time, now());
is($interval->[2],14);

$delta = 14 * 24 * 60 * 60;
is($time, $schedule->calcNextTime($time, $interval) - $delta);

diag('week interval format');
($time, $interval, $priority) = $schedule->readTime('2w');
is($time, now());
is($interval->[2],14);

$delta = 14 * 24 * 60 * 60;
is($time, $schedule->calcNextTime($time, $interval) - $delta);

my @words = qw(mon tu tue tues wed th thu thur fri sat sun);
my @dows = qw(1 2 2 2 3 4 4 4 5 6 7);
my $i = 0;
foreach my $w (@words) {
	diag("day of week - test word $w");
	($time, $interval, $priority) = $schedule->readTime($w);
	
	ok($time > now());
	is($interval->[2],7);
	
	my @t = Time_to_Date($time);
	is(Day_of_Week(@t[0..2]), $dows[$i++]);
	is($t[$_], 0) foreach 3..5;
}

@words = qw(2sat 3sun 4mon);
@dows = qw(6 7 1);
my @dd = qw(14 21 28);
$i = 0;
foreach my $w (@words) {
	diag("day of week - test word $w");
	($time, $interval, $priority) = $schedule->readTime($w);
	
	ok($time > now());
	is($interval->[2], $dd[$i]);
	
	my @t = Time_to_Date($time);
	is(Day_of_Week(@t[0..2]), $dows[$i++]);
	is($t[$_], 0) foreach 3..5;
}

foreach my $w ('2sun16:38', '2sun 16:38') {
	diag("day of week - test word $w");
	($time, $interval, $priority) = $schedule->readTime($w);
	ok($time > now());
	is($interval->[2], 14);
	my @t = Time_to_Date($time);
	is(Day_of_Week(@t[0..2]), 7);
	is($t[3], 16);
	is($t[4], 38);
	is($t[5], 0);
}