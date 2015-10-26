use lib "../lib";

use strict;

use TAP::Harness;
use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	items => [
		"Unit test file",
		"Directory"
	],
	options => [
		[ "h help",   "See this help" ],
		[ "all",      "Runs all avaialbale tests" ],
		[ "platform", "Runs platform test only" ],
		[ "product",  "Runs product test only" ],
		[ "dump",     "Dumps the test results" ],
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
