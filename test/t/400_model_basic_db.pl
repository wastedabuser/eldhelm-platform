use strict;

use lib '..';
use lib '../..';
use lib '../../platform/lib';
use lib '../lib';
use lib '../../lib';

use Test::More;
use Data::Dumper;
use Eldhelm::Database::Pool;
use Eldhelm::Util::Factory;

my ($index, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do '../../config.pl' or die 'Can not read config!';

Eldhelm::Database::Pool->new(config => $config);
my $model = Eldhelm::Util::Factory->instance($className);

ok($model->{table}, 'table defined');

eval {
	my $desc = $model->desc;
	ok(ref $desc eq 'ARRAY', 'table exists');
	1;
} or do {
	diag($@);
	fail('table exists');
};

