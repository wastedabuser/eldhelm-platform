use strict;
use lib "../lib";
use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;
use Eldhelm::Util::Factory;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	options => [
		[ "all",      "checks all code" ],
		[ "platform", "check platform code only" ],
		[ "util",     "check platform utils code only" ],
		[ "product",  "check product code only" ],
		[ "dump",     "show verbose output" ],
	]
);

if (!@ARGV) {
	print $cmd->usage;
	exit;
}

my %ops = $cmd->arguments;

my @libPaths = ("../lib", "../../platform-utils/lib", "../../");

my @defaultPats;
push @defaultPats, "../lib"                   if $ops{platform} || $ops{all};
push @defaultPats, "../../platform-utils/lib" if $ops{util}     || $ops{all};
push @defaultPats, "../../Eldhelm"            if $ops{product}  || $ops{all};

my @sources;
my $si;
foreach (@defaultPats, @{ $ops{list} }) {
	if (-f $_) {
		push @sources, $_;
		next;
	}
	my $flag;
	my $p = m|/| ? $_ : Eldhelm::Util::Factory->pathFromNotation("../../Eldhelm", $_);
	if (-d $p) {
		push @sources, grep { /(?:\.pm|\.pl)$/ } Eldhelm::Util::FileSystem->readFileList($p);
		$flag = 1;
	} elsif (-f $p) {
		push @sources, $p;
		$flag = 1;
	}
	if (-f "$p.pm") {
		push @sources, "$p.pm";
		$flag = 1;
	}
	unless ($flag) {
		print "[Skip] $p is neither a folder nor a package!\n";
		$si++;
	}
}

my %testScripts;
foreach my $s (@sources) {
	my $f  = Eldhelm::Util::FileSystem->getFileContents($s);
	my @ts = $f =~ /###\s*TEST SCRIPT:\s*(.+?)\s*###/g;
	next unless @ts;

	$testScripts{$s} = \@ts;
}

my ($i, $ei, $oi) = (0, 0, 0);
my $inc = join " ", map { qq~-I "$_"~ } @libPaths;
my @errors;
foreach my $s (@sources) {
	print "Static analysis [$s] ... ";
	my $res;
	my $output = `perl $inc -Ttcw "$s" 2>&1`;
	$output =~ s/\n/\n\t/g;
	$output = "\t$output";
	if (index($output, "syntax OK") >= 0) {
		print "OK\n";
		$res = 1;
	} else {
		push @errors, [ $i, $s, $output ];
		print "FAILED\n";
		$res = 0;
	}
	print "$output\n" if $ops{dump};
	next unless $res;

	if ($testScripts{$s}) {
		print "Dynamic analysis [$s] ... ";
		print "\n\tRunning the following tests:\n".join("\n", map { "\t$_" } @{ $testScripts{$s}})."\n" if $ops{dump};
		my $ts = join " ", map { -f("../../test/t/$_") ? qq~"../../test/t/$_"~ : qq~"t/$_"~ } @{ $testScripts{$s} };
		my $testResult = `perl runner.pl $ts 2>&1`;
		$testResult =~ s/\n/\n\t/g;
		$testResult = "\t$testResult";
		if (index($testResult, "Result: PASS") >= 0) {
			print "OK\n";
			$res = 1;
		} else {
			push @errors, [ $i, $s, $testResult];
			print "FAILED\n";
			$res = 0;
		}
		print "$testResult\n" if $ops{dump};
	}

	$ei++ unless $res;
	$oi++ if $res;
	$i++;
}

if (@errors) {
	print "=============================================\n";
	print "$ei FAILED;\n";
	print "=============================================\n";
	foreach (@errors) {
		my ($ind, $name, $output) = @$_;
		print "Failed $ind [$name]\n$output\n";
	}
}
print "=============================================\n";
print "$ei FAILED; " if $ei;
print "$si SKIPPED; " if $si;
print "$oi OK; $i files checked;\n";
print "=============================================\n";
