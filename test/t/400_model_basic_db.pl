use strict;

use lib '..';
use lib '../..';
use lib '../../platform/lib';
use lib '../lib';
use lib '../../lib';

use Test::More;
use Data::Dumper;
use Eldhelm::Test::Mock::Worker;
use Eldhelm::Database::Pool;
use Eldhelm::Util::Factory;
use Eldhelm::Util::FileSystem;

my ($index, $configPath, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do($configPath || '../../config.pl') or die 'Can not read config!';
my $worker = Eldhelm::Test::Mock::Worker->new(config => $config);

diag('Verifying construction');

Eldhelm::Database::Pool->new(config => $config);
my $model = Eldhelm::Util::Factory->instance($className);

ok($model->{table}, 'table defined');

eval {
	my $desc = $model->desc;
	ok(ref $desc eq 'ARRAY', 'table exists');
	1;
} or do {
	diag($@);
	fail('table does not exist');
};

my $source = Eldhelm::Util::FileSystem->getFileContents($sourceContext);
my @allResources;

diag('Verifying models');
my %models = map { +$_ => 1 } $source =~ /getModel\((.*?)\)/g;
foreach (keys %models) {
	my $val = eval("[$_]");
	next unless $val;

	my ($name, $args) = @$val;
	push @allResources, $name;
	eval {
		my $m = $model->getModel($name, $args);
		ok($m, "Model $name ok");
	} or do {
		note($@);
		fail("Model $name is missing!");
	};
}

diag(Dumper \@allResources);

diag('Verifing queries');
my %queries = map { +$_ => 1 } $source =~ /qq\|(.*?)\|/gs;
my $sql = $model->{dbPool}->getDb;
my @queriesList = keys %queries;
foreach my $q (@queriesList) {
	my @args = map { 'unit-test-stub-value' } $q =~ /(\?)/g;
	eval {
		$sql->query($q, @args);
		ok(1, 'Query seems OK');
	} or do {
		note($@);
		fail("Query failed!\n$@");
	};
}

diag(scalar(@queriesList).' SQL Queries tested!');