use strict;

use lib '..';
use lib '../..';
use lib '../../platform/lib';
use lib '../lib';
use lib '../../lib';

use Test::More;
use Data::Dumper;
use Eldhelm::Util::Factory;
use Eldhelm::Util::FileSystem;
use Eldhelm::Test::Mock::Worker;

my ($index, $configPath, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do($configPath || '../../config.pl') or die 'Can not read config!';
my $worker = Eldhelm::Test::Mock::Worker->new(config => $config);

diag("Verifying construction");
my $persist = Eldhelm::Util::Factory->instance($className);
my $source = Eldhelm::Util::FileSystem->getFileContents($sourceContext);

ok($persist->id, 'has id');
ok($persist->persistType, 'has persistType');

my @allResources;

diag("Verifying models");
my %models = map { +$_ => 1 } $source =~ /getModel\((.*?)\)/g;
foreach (keys %models) {
	my $val = eval("[$_]");
	next unless $val;

	my ($name, $args) = @$val;
	push @allResources, $name;
	eval {
		my $model = $persist->getModel($name, $args);
		ok($model, "Model $name ok");
	} or do {
		note($@);
		fail("Model $name is missing!");
	};
}

diag(Dumper \@allResources);
