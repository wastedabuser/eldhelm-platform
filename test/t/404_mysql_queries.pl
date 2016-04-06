use strict;

use lib '..';
use lib '../..';
use lib '../../platform/lib';
use lib '../lib';
use lib '../../lib';

use Test::More;
use Data::Dumper;
use Eldhelm::Database::Pool;
use Eldhelm::Util::FileSystem;

my ($index, $configPath, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do($configPath || '../../config.pl') or die 'Can not read config!';
my $dbPool = Eldhelm::Database::Pool->new(config => $config);
my $source = Eldhelm::Util::FileSystem->getFileContents($sourceContext);

diag('Verifing queries');
my @parts = $source =~ /(q?q\|.*?)\|/gs;
my %queries;
foreach (@parts) {
	my ($quote, $query) = split /\|/;
	if ($queries{$query}) {
		note($query);
		fail("Same query multiple times!\n $query");
	} else {
		$queries{$query} = $quote;
		pass('Query extracted');
	}
}
my $sql = $dbPool->getDb;
my @queriesList = keys %queries;
foreach my $q (@queriesList) {
	if ($q =~ /(?:insert|replace|delete|update)/i) {
		# $q = "EXPLAIN $q"; mysql 5.6.3
		note($q);
		pass('NON SELECT queries will not be executed!');
		next;
	}
	
	my $quote = $queries{$q};
	$q =~ s/\$\w+//g if $quote eq 'qq';
	$q =~ s/\[\w+(.+?)\]/$1/ge;
	my @args = map { 'unit-test-stub-value' } $q =~ /(\?)/g;
	eval {
		$sql->query($q, @args);
		pass('Query seems OK');
	} or do {
		note($@);
		fail("Query failed!\n$@");
	};
}

diag(scalar(@queriesList).' SQL Queries tested!');
pass('Should be ok!') unless @queriesList;