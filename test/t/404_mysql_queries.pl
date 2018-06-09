use strict;

use lib '..';
use lib '../..';
use lib '../../platform/lib';
use lib '../../platform-utils/lib';
use lib '../lib';
use lib '../../lib';

use Test::More;
use Data::Dumper;
use Eldhelm::Database::Pool;
use Eldhelm::Util::FileSystem;
use Eldhelm::Database::Template;
use Eldhelm::Util::Factory;

my ($index, $configPath, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do($configPath || '../../config.pl') or die 'Can not read config!';
my $dbPool = Eldhelm::Database::Pool->new(config => $config);
my $source = Eldhelm::Util::FileSystem->getFileContents($sourceContext);
my $model  = Eldhelm::Util::Factory->instance($className);

diag('Verifing queries');
my @parts = $source =~ /(q?q\|.*?)\|/gs;
my @fixtureParts = $source =~ /### QUERY FIXTURE:(.+?)###/gs;

if (@fixtureParts && @parts != @fixtureParts) {
	fail('Query test fixtures must be provided for all queries');
}

my %queries;
my %fixtures;
foreach (@parts) {
	my ($quote, $query) = split /\|/;
	my $fixture = shift @fixtureParts;
	
	if ($queries{$query}) {
		note($query);
		fail("Same query multiple times!\n $query");
	} else {
		$queries{$query} = $quote;
		
		if ($fixture) {
			$fixtures{$query} = eval $fixture;
			fail("Fixture evaluation failed: $@") if $@;
		}
		
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
	my $fixture = $fixtures{$q};
	
	if ($quote eq 'qq') {
		$q =~ s/\$self->\{table\}/$model->{table}/ge;
		$q =~ s/\(\$\w+\)/\('unit-test-stub-value'\)/g;
		$q =~ s/`\$(\w+)`/`\1`/g;
		$q =~ s/\$\w+//g;
	}
	if ($q =~ /[\[\{]/) {
		note('This query seems to be a template');
		fail("Fixture is not a hashref: ".Dumper($fixture)) if $fixture && ref($fixture) ne 'HASH';
			
		my $tpl = Eldhelm::Database::Template->new(
			sql    => $sql,
			stream => $q,
			$fixture ? %$fixture : ()
		);
		$q = $tpl->compile;	
		note($q);
	}
	
	my @args;
	if ($fixture && ref($fixture) eq 'ARRAY') {
		@args = @$fixture;
	} else {
		@args = map { 'unit-test-stub-value' } $q =~ /(\?)/g;
	}
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