use lib '../lib';

use strict;
use warnings;

use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;
use Eldhelm::Util::Factory;
use Eldhelm::Perl::SourceParser;
use Eldhelm::Pod::Parser;
use Eldhelm::Pod::Validator;
use Eldhelm::Pod::DocCompiler;
use Eldhelm::Test::Unit;
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
		[ 'prefix',   'adds a prefix to all listed files' ],
		[ 'dump',     'show verbose output' ],
		[ 'syntax',   'check syntax' ],
		[ 'static',   'run static anlysis using Perl::Critic' ],
		[ 'unittest', 'run all unit tests for specified source code' ],
		[ 'autotest', 'run only the default auto tests' ],
		[ 'doc',      'check pod documentation' ],
		[ 'config',   'path to server config (required by some unit tests)' ],
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

my @listed;
if ($ops{prefix}) {
	@listed = map { "$ops{prefix}$_" } @{ $ops{list} };
} else {
	@listed = @{ $ops{list} };
}

my $err = "[Skip] %s is neither a folder nor a perl source!\n";
my @sources;
my $si;
foreach (@defaultPats, @listed) {
	if (-f $_) {
		if (/(?:\.pm|\.pl)$/) {
			push @sources, $_;
		} else {
			print sprintf($err, $_);
		}
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
		print sprintf($err, $p);
		$si++;
	}
}

my $critic = Perl::Critic->new(-profile => 'perlcritic.config');
my ($i, $fi, $oi) = (0, 0, 0);
my $inc = join ' ', map { qq~-I "$_"~ } @libPaths;
my @errors;

sub checkSyntax {
	my ($s, $i) = @_;
	print " - Syntax check $i [$s] ... ";
	my $output = `perl $inc -Ttcw "$s" 2>&1`;
	$output =~ s/\n/\n\t/g;
	$output = "\t$output";

	if (index($output, 'syntax OK') >= 0) {
		print "OK\n";
		print "$output\n" if $ops{dump};
		return 1;
	}

	push @errors, [ $i, $s, $output ];
	print "FAILED\n\n";
	return;
}

sub runPerlCritic {
	my ($s, $i) = @_;
	print " - Static analysis $i [$s] ... ";
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
	my ($s, $i, $scope) = @_;

	my $unit = Eldhelm::Test::Unit->new(file => $s);
	my $sData = $unit->sourceData;
	my ($className, $parentClassName) = ($sData->{className}, $sData->{extends}[0]);
	my $testFiles = $scope eq 'auto' ? [] : $unit->unitTests;
	if ($className) {
		if ($className =~ /^Eldhelm::Application::Controller/) {
			unshift @$testFiles, "401_controller_basic.pl";
		} elsif ($className =~ /^Eldhelm::Application::Model/) {
			if ($parentClassName =~ /BasicDb/) {
				unshift @$testFiles, "400_model_basic_db.pl";
			}
		} elsif ($className =~ /^Eldhelm::Application::Persist/) {
			unshift @$testFiles, "402_persist_basic.pl";
		} elsif ($className =~ /^Eldhelm::Application::View/) {
			unshift @$testFiles, "403_view_basic.pl";
		}
	}
	
	if (!$testFiles || !@$testFiles) {
		print "[Skip] No unit tests defined for $i [$s]\n\n" if $ops{dump};
		return 1;
	}
	
	my $lbl = " - Unit test $i [$s] ... ";
	print $lbl;
	print "\n\tRunning the following tests:\n".join("\n", map { "\t- $_" } @$testFiles,)."\n" if $ops{dump};
	my $ts         = join ' ', map { -f ("../../test/t/$_") ? qq~"../../test/t/$_"~ : qq~"t/$_"~ } @$testFiles,;
	my $z          = 1;
	my $args       = join ' ', ($ops{config} ? "-config $ops{config}" : ()), map { "-arg".($z++).qq~ "$_"~ } $s, $className;
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
	print "FAILED\n\n";
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

	my $lbl = " - Compiling POD $i [$s] ... ";
	print "$lbl OK\n";
	print Eldhelm::Pod::DocCompiler->new(rootPath => '../lib/')->compileParsed('pod.class', $p);
	print "\n\n";

	return 1;

	# print "FAILED\n";
	# return;
}

foreach my $s (@sources) {
	$i++;
	my @oks = (1,1,1,1);

	print "$i. Working on [$s]\n";
	
	if ($ops{syntax}) {
		next unless $oks[0] = checkSyntax($s, $i);
	}

	if ($ops{unittest}) {
		$oks[1] = runUnitTests($s, $i, 'all');
	} elsif ($ops{autotest}) {
		$oks[1] = runUnitTests($s, $i, 'auto');
	}
	
	if ($ops{static}) {
		$oks[2] = runPerlCritic($s, $i);
	}
	
	if ($ops{doc}) {
		$oks[3] = runDocCheck($s, $i);
	}

	$oi++ if $oks[0] && $oks[1];
	$fi++ if grep { !$_ } @oks;
}

my $hr =
	"=======================================================================================================================================\n";
my $result;
if (@errors) {
	$result .= $hr;
	$result .= "WARN=$fi; " if $fi;
	$result .= 'ERRORS='.scalar(@errors).";\n";
	$result .= $hr;
	foreach (@errors) {
		my ($ind, $name, $output) = @$_;
		$result .= "Failed $ind [$name]\n$output\n";
	}
}
$result .= $hr;
$result .= "WARN=$fi/$i; " if $fi;
$result .= "PASS=$oi/$i; ";
$result .= "SKIPPED=$si; " if $si;
$result .= 'ERRORS='.scalar(@errors).'; ' if @errors;
$result .= "CHECKED=$i;\n";
$result .= $hr;

if ($oi != $i) {
	die $result;
} else {
	print $result;
}