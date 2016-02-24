use lib '../lib';

use strict;

use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	options => [
		[ 'h help', 'see this help' ],
		[ 't',      'test folder' ],
		[ 'p',      'production folder' ],
		[ 'n',      'print one file per line' ],
		[ 'q',      'return quoted paths' ],
		[ 'fp',     'return full paths' ]
	],
	examples => [ "perl $0 -t /home/eldhelm/deploy -p /home/eldhelm/server", ]
);

my %ops = $cmd->arguments;
if (!@ARGV || $ops{h} || $ops{help}) {
	print $cmd->usage;
	exit;
}

my ($test, $production) = ($ops{t}, $ops{p});
die "No test folder specified"       unless $test;
die "No production folder specified" unless $production;
die "$test folder invalid"           unless -d $test;
die "$production folder invalid"     unless -d $production;

my @tList = Eldhelm::Util::FileSystem->readFileList($test);
s/^$test// foreach @tList;
my @pList = Eldhelm::Util::FileSystem->readFileList($production);
s/^$production// foreach @pList;

sub getMeta {
	my ($path, $list) = @_;
	my $lookup = {};
	foreach my $f (@$list) {
		my $p = "$path/$f";
		my @s = stat($p);
		$lookup->{$f} = [ $s[7], $s[9] ];
	}
	return $lookup;
}

my $tMap = getMeta($test, \@tList);
my $pMap = getMeta($production, \@pList);

my @manifest;
foreach my $f (keys %$tMap) {
	unless ($pMap->{$f}) {
		push @manifest, $f;
		next;
	}
	my $t = $tMap->{$f};
	my $p = $pMap->{$f};

	if ($t->[0] != $p->[0] || $t->[1] > $p->[1]) {
		push @manifest, $f;
		next;
	}
}

if ($ops{fp}) {
	$_ = $test.$_ foreach @manifest;
}

@manifest = sort { $a cmp $b } @manifest;
if ($ops{n}) {
	foreach (@manifest) {
		print "$_\n";
	}
} elsif ($ops{q}) {
	print join ' ', map { qq~"$_"~ } @manifest;
} else {
	print join ' ', @manifest;
}
