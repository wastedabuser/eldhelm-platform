use strict;
use lib "../lib";
use TAP::Harness;
use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;

my %ops = Eldhelm::Util::CommandLine->parseArgv(@ARGV);

if (!@ARGV) {
	print "Usage:
perl $0 [list of folders names or files]\n
Options:
	-all runs all avaialbale tests
	-dump dumps the test results
\n";
	exit;
}

my $harness = TAP::Harness->new({ verbosity => $ops{dump} || 0, });

my @tests;
@tests = Eldhelm::Util::FileSystem->readFileList("t") if $ops{all};
$harness->runtests(sort { $a cmp $b } @tests);
