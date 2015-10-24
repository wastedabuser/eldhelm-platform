use strict;
use lib "../lib";
use TAP::Harness;
use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	items => [
		"unit test file",
		"directory"
	],
	options => [
		[ "h help",   "see this help" ],
		[ "all",      "runs all avaialbale tests" ],
		[ "platform", "runs platform test only" ],
		[ "product",  "runs product test only" ],
		[ "dump",     "dumps the test results" ],
	]
);

my %ops = $cmd->arguments;
if (!@ARGV || $ops{h} || $ops{help}) {
	print $cmd->usage;
	exit;
}

my $harness = TAP::Harness->new({ verbosity => $ops{dump} || 0 });

my @defaultPaths;
push @defaultPaths, "t"            if $ops{platform} || $ops{all};
push @defaultPaths, "../../test/t" if $ops{product}  || $ops{all};

my @tests;
if ($ops{list}) {
	push @defaultPaths, grep { -d } @{ $ops{list} };
	push @tests,        grep { -f } @{ $ops{list} };
}

foreach (@defaultPaths) {
	push @tests, grep { /\.pl$/ } Eldhelm::Util::FileSystem->readFileList($_);
}

$harness->runtests(sort { $a cmp $b } @tests);
