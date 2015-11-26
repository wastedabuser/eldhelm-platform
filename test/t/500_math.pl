use strict;
use lib '../lib';
use lib '../../lib';
use Test::More 'no_plan';

use Data::Dumper;
use Eldhelm::Util::Math;

diag("max function");
my $data1 = [ { a => 1 }, { a => 3 }, { a => 2 }, ];
my $data2 = [ { a => { b => 2 } }, { a => { b => 1 } }, { a => { b => 3 } }, ];
ok(Eldhelm::Util::Math->max($data1, 'a') == 3);
ok(Eldhelm::Util::Math->max($data2, [ 'a', 'b' ]) == 3);

diag("max function is non destructive");
ok(scalar(@$data1) == 3);
ok(ref $data1->[0] eq 'HASH');
ok($data1->[0]{a} == 1);
ok($data1->[1]{a} == 3);

ok(scalar(@$data2) == 3);
ok(ref $data2->[0] eq 'HASH');
ok(ref $data2->[0]{a} eq 'HASH');
ok($data2->[0]{a}{b} == 2);
ok($data2->[1]{a}{b} == 1);

diag("min function");
$data1 = [ { a => 1 }, { a => 3 }, { a => 2 }, ];
$data2 = [ { a => { b => 2 } }, { a => { b => 1 } }, { a => { b => 3 } }, ];
ok(Eldhelm::Util::Math->min($data1, 'a') == 1);
ok(Eldhelm::Util::Math->min($data2, [ 'a', 'b' ]) == 1);

diag("min function is non destructive");
ok(scalar(@$data1) == 3);
ok(ref $data1->[0] eq 'HASH');
ok($data1->[0]{a} == 1);
ok($data1->[1]{a} == 3);

ok(scalar(@$data2) == 3);
ok(ref $data2->[0] eq 'HASH');
ok(ref $data2->[0]{a} eq 'HASH');
ok($data2->[0]{a}{b} == 2);
ok($data2->[1]{a}{b} == 1);
