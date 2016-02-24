use lib '../lib';

use strict;

use Data::Dumper;
use Eldhelm::Util::CommandLine;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv    => \@ARGV,
	items => [ 'files' ],
	options => [
		[ 'h help', 'see this help' ],
		[ 't',      'test folder' ],
		[ 'p',      'production folder' ],
	],
	examples => [ "perl $0 my_file.pl -t /home/eldhelm/deploy -p /home/eldhelm/server", ]
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

foreach (@{ $ops{list} }) {
	my ($f, $t) = ("$test$_", "$production$_");
	
	(my $d = $t) =~ s/[^\/]+$//;
	if (!-d $d) {
		`mkdir $d`;
		print "Creating dir $d\n";
	} 
	
	`cp $f $t`;
	print "Copying $f to $t\n";
}