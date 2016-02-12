use lib '../lib';

use strict;
use warnings;

use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;
use Eldhelm::Util::Factory;
use Eldhelm::Pod::Parser;
use Eldhelm::Pod::Validator;
use Eldhelm::Pod::DocCompiler;
use Perl::Critic;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	items   => [ 'Source file', 'Source directory', 'Dotted notation of a class' ],
	options => [
		[ 'h help',   'see this help' ],
		[ 'all',      'checks all code' ],
		[ 'platform', 'check platform code only' ],
		[ 'util',     'check platform utils code only' ],
		[ 'product',  'check product code only' ],
		[ 'dump',     'show verbose output' ],
		[ 'syntax',   'check syntax' ],
		[ 'static',   'run static anlysis using Perl::Critic' ],
		[ 'unittest', 'run unit tests referenced in the source' ],
		[ 'doc',      'check pod documentation' ],
	],
	examples => [
		"perl check.pl -all -syntax -static -unittest",
		"perl check.pl /home/me/myproject/Eldhelm/Application/Controller/Test.pm -syntax",
		"perl check.pl myNamespace.myController -syntax",
	]
);

my %ops = $cmd->arguments;
if (!@ARGV || $ops{h} || $ops{help}) {
	print $cmd->usage;
	exit;
}

my @libPaths = ('../lib', "../../platform-utils/lib", '../../');

my @defaultPats;
push @defaultPats, '../lib'                   if $ops{platform} || $ops{all};
push @defaultPats, "../../platform-utils/lib" if $ops{util}     || $ops{all};
push @defaultPats, '../../Eldhelm'            if $ops{product}  || $ops{all};

my @sources;
my $si;
foreach (@defaultPats, @{ $ops{list} }) {
	if (-f $_) {
		push @sources, $_;
		next;
	}
	my $flag;
	my $p = m|/| ? $_ : Eldhelm::Util::Factory->pathFromNotation('../../Eldhelm', $_);
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

	my ($className) = $f =~ /package[\s\t]+(.+?)[\s\t]*?;/;
	$testScripts{$s} = [ \@ts, $className ];
}

my $critic = Perl::Critic->new(-profile => 'perlcritic.config');
my ($i, $fi, $oi) = (0, 0, 0);
my $inc = join ' ', map { qq~-I "$_"~ } @libPaths;
my @errors;

sub checkSyntax {
	my ($s, $i) = @_;
	print "Syntax check $i [$s] ... ";
	my $output = `perl $inc -Ttcw "$s" 2>&1`;
	$output =~ s/\n/\n\t/g;
	$output = "\t$output";

	if (index($output, 'syntax OK') >= 0) {
		print "OK\n";
		print "$output\n" if $ops{dump};
		return 1;
	}

	push @errors, [ $i, $s, $output ];
	print "FAILED\n";
	return;
}

sub runPerlCritic {
	my ($s, $i) = @_;
	print "Static analysis $i [$s] ... ";
	if ($s =~ /.pl$/) {
		print "SKIP\n";
		print "\tThis is a perl script not a package\n\n" if $ops{dump};
		return 1;
	}
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
	my ($s, $i) = @_;

	my $tests = $testScripts{$s};
	unless ($tests) {
		print "[Skip] No unit tests defined for $i [$s]\n\n" if $ops{dump};
		return 1;
	}
	my ($testFiles, @testArgs) = @$tests;

	my $lbl = "Unit tests $i [$s] ... ";
	print $lbl;
	print "\n\tRunning the following tests:\n".join("\n", map { "\t- $_" } @$testFiles,)."\n" if $ops{dump};
	my $ts         = join ' ', map { -f ("../../test/t/$_") ? qq~"../../test/t/$_"~ : qq~"t/$_"~ } @$testFiles,;
	my $z          = 1;
	my $args       = join ' ', map { "-arg".($z++).qq~ "$_"~ } $s, @testArgs;
	my $testResult = `perl runner.pl $ts $args 2>&1`;
	$testResult =~ s/\n/\n\t/g;
	$testResult = "\t$testResult";

	if (index($testResult, 'Result: PASS') >= 0) {
		print $ops{dump} ? (' ' x length($lbl))."OK\n" : "OK\n";
		print "$testResult\n" if $ops{dump};
		return 1;
	}
	if (index($testResult, 'Result: NOTESTS') >= 0) {
		print "$testResult\n" if $ops{dump};
		return 1;
	}

	push @errors, [ $i, $s, $testResult ];
	print "FAILED\n";
	return;
}

sub runDocCheck {
	my ($s, $i) = @_;

	my $p = Eldhelm::Pod::Parser->new(file => $s, libPath => '../lib');
	unless ($p->hasDoc) {
		print "[Skip] No POD for $i [$s]\n\n" if $ops{dump};
		return 1;
	}

	my @violations = Eldhelm::Pod::Validator->new(parser => $p)->validate;
	if (@violations) {
		push @errors, [ $i, $s, join("", map { "\t$_\n" } @violations) ];
		print "POD ISSUES\n";
		print "\t".scalar(@violations)." issues found\n\n" if $ops{dump};
		return;
	}
	
	my $lbl = "Compiling POD $i [$s] ... ";
	print "$lbl OK\n";
	print Eldhelm::Pod::DocCompiler->new(rootPath => '../lib/')->compileParsed('pod.class', $p);
	print "\n\n";

	return 1;

	# print "FAILED\n";
	# return;
}

foreach my $s (@sources) {
	$i++;
	my $ok;

	if ($ops{syntax}) {
		$ok = checkSyntax($s, $i);
		next unless $ok;
	}

	if ($ops{static}) {
		$ok = runPerlCritic($s, $i);
	}

	if ($ops{unittest}) {
		$ok = runUnitTests($s, $i);
	}

	if ($ops{doc}) {
		$ok = runDocCheck($s, $i);
	}

	$fi++ unless $ok;
	$oi++ if $ok;
}

my $hr =
	"=======================================================================================================================================\n";
if (@errors) {
	print $hr;
	print "FAILED=$fi; " if $fi;
	print 'ERRORS='.scalar(@errors).";\n";
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
print 'ERRORS='.scalar(@errors).'; ' if @errors;
print "CHECKED=$i;\n";
print $hr;
