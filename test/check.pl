use lib "../lib";

use strict;
use warnings;

use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;
use Eldhelm::Util::Factory;
use Perl::Critic;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	options => [
		[ "all",      "checks all code" ],
		[ "platform", "check platform code only" ],
		[ "util",     "check platform utils code only" ],
		[ "product",  "check product code only" ],
		[ "dump",     "show verbose output" ],
		[ "syntax",   "check syntax" ],
		[ "static",   "run static anlysis using perl::crytic" ],
		[ "unittest", "run unit tests refernced in the source" ],
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
	my @ts = $f =~ /###\s*UNIT TEST:\s*(.+?)\s*###/g;
	next unless @ts;

	$testScripts{$s} = \@ts;
}

my $critic = Perl::Critic->new(-profile => "perlcritic.config");
my ($i, $fi, $oi) = (0, 0, 0);
my $inc = join " ", map { qq~-I "$_"~ } @libPaths;
my @errors;

sub checkSyntax {
	my ($s) = @_;
	print "Syntax check $i [$s] ... ";
	my $output = `perl $inc -Ttcw "$s" 2>&1`;
	$output =~ s/\n/\n\t/g;
	$output = "\t$output";

	if (index($output, "syntax OK") >= 0) {
		print "OK\n";
		print "$output\n" if $ops{dump};
		return 1;
	}

	push @errors, [ $i, $s, $output ];
	print "FAILED\n";
	return;
}

sub runPerlCritic {
	my ($s) = @_;
	print "Static analysis $i [$s] ... ";
	my @violations = $critic->critique($s);

	if (@violations) {
		push @errors, [ $i, $s, join("", map { "\t$_" } @violations) ];
		print "VIOLATED\n";
		print "\t".scalar(@violations)." violations found\n\n" if $ops{dump};
		return;
	}

	print "OK\n";
	print "\tNo violations\n\n" if $ops{dump};
	return 1;
}

sub runUnitTests {
	my ($s) = @_;

	unless ($testScripts{$s}) {
		print "[Skip] No unit tests defined for $i [$s]\n\n" if $ops{dump};
		return 1;
	}

	my $lbl = "Unit tests $i [$s] ... ";
	print $lbl;
	print "\n\tRunning the following tests:\n".join("\n", map { "\t- $_" } @{ $testScripts{$s} })."\n" if $ops{dump};
	my $ts = join " ", map { -f ("../../test/t/$_") ? qq~"../../test/t/$_"~ : qq~"t/$_"~ } @{ $testScripts{$s} };
	my $testResult = `perl runner.pl $ts 2>&1`;
	$testResult =~ s/\n/\n\t/g;
	$testResult = "\t$testResult";

	if (index($testResult, "Result: PASS") >= 0) {
		print $ops{dump} ? (" " x length($lbl))."OK\n" : "OK\n";
		print "$testResult\n" if $ops{dump};
		return 1;
	}

	push @errors, [ $i, $s, $testResult ];
	print "FAILED\n";
	return;
}

foreach my $s (@sources) {
	$i++;
	my $ok;

	if ($ops{syntax}) {
		$ok = checkSyntax($s);
		next unless $ok;
	}

	if ($ops{static}) {
		$ok = runPerlCritic($s);
	}

	if ($ops{unittest}) {
		$ok = runUnitTests($s);
	}

	$fi++ unless $ok;
	$oi++ if $ok;
}

my $hr =
	"=======================================================================================================================================\n";
if (@errors) {
	print $hr;
	print "FAILED=$fi; " if $fi;
	print "ERRORS=".scalar(@errors).";\n";
	print $hr;
	foreach (@errors) {
		my ($ind, $name, $output) = @$_;
		print "Failed $ind [$name]\n$output\n";
	}
}
print $hr;
print "FAILED=$fi/$i; " if $fi;
print "OK=$oi/$i; ";
print "SKIPPED=$si; " if $si;
print "ERRORS=".scalar(@errors)."; " if @errors;
print "CHECKED=$i;\n";
print $hr;
