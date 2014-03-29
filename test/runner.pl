use strict;
use lib "../lib";
use TAP::Harness;
use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv  => \@ARGV,
	usage => [
		[ "all",      "runs all avaialbale tests" ],
		[ "platform", "runs platform test only" ],
		[ "product",  "runs product test only" ],
		[ "dump",     "dumps the test results" ],
	]
);

if (!@ARGV) {
	print $cmd->usage;
	exit;
}

my %ops = $cmd->arguments;
my $harness = TAP::Harness->new({ verbosity => $ops{dump} || 0, });

my @defaultPats;
push @defaultPats, "t"            if $ops{platform} || $ops{all};
push @defaultPats, "../../test/t" if $ops{product}  || $ops{all};

my @tests;
foreach (@defaultPats, @{ $ops{list} }) {
	push @tests, grep { /\.pl$/ } Eldhelm::Util::FileSystem->readFileList($_);
}

$harness->runtests(sort { $a cmp $b } @tests);
