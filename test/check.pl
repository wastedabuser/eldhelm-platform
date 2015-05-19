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
		[ "dump",  	  "show verbose output"],
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
foreach (@defaultPats, @{ $ops{list} }) {
	my $p = m|/| ? $_ : Eldhelm::Util::Factory->pathFromNotation("../../Eldhelm", $_);
	if (-d $p) {
		push @sources, grep { /(?:\.pm|\.pl)$/ } Eldhelm::Util::FileSystem->readFileList($p);
	} elsif (-f "$p.pm") {
		push @sources, "$p.pm";
	} else {
		print "[Skip] $p is neither a folder nor a package!\n";
	}
}

my ($i, $ei, $oi) = (0, 0, 0);
my $inc = join " ", map { qq~-I "$_"~ } @libPaths;
my @errors;
foreach (@sources) {
	print "Checking [$_] ... ";
	my $output = `perl $inc -Ttcw "$_" 2>&1`;
	if ($output !~ /syntax OK/) {
		push @errors, [$i, $_, $output];
		$ei++;
		print "FAILED\n";
	} else {
		$oi++;
		print "OK\n";
	}
	print "$output\n" if $ops{dump};
	$i++;
}

print "=============================================\n";
print "$ei FAILED; $oi OK; $i files checked;\n";
print "=============================================\n";

foreach (@errors) {
	my ($ind, $name, $output) = @$_;
	print "Failed $ind [$name]\n$output\n";
}