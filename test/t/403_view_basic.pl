use strict;

use lib '..';
use lib '../..';
use lib '../../platform/lib';
use lib '../lib';
use lib '../../lib';

use Test::More;
use Data::Dumper;
use Eldhelm::Util::Factory;
use Eldhelm::Test::Mock::Worker;

my ($index, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do '../../config.pl' or die 'Can not read config!';
my $worker = Eldhelm::Test::Mock::Worker->new(config => $config);

diag("Verifying construction");

Eldhelm::Database::Pool->new(config => $config);
my $view = Eldhelm::Util::Factory->instance($className);
ok(ref $view);
