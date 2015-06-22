use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Util::Tool qw(isIn);

diag("isIn, isNotIn");

ok(!$@, "ok, no error");
eval {
	isNotIn("a", qw(a b c));
};
ok($@, "isNotIn not exported");

ok(isIn("a", qw(a b c)), "exported and working");
ok(isIn("b", qw(a b c)));
ok(isIn("c", qw(a b c)));
ok(!isIn("d", qw(a b c)));
ok(!isIn("e", qw(a b c)));
ok(!isIn("f", qw(a b c)));
ok(isIn(1, qw(1 2 3)));
ok(isIn(2, qw(1 2 3)));
ok(isIn(3, qw(1 2 3)));
ok(!isIn(4, qw(1 2 3)));

ok(!Eldhelm::Util::Tool->isNotIn("a", qw(a b c)));
ok(!Eldhelm::Util::Tool->isNotIn("b", qw(a b c)));
ok(!Eldhelm::Util::Tool->isNotIn("c", qw(a b c)));
ok(Eldhelm::Util::Tool->isNotIn("d", qw(a b c)));
ok(Eldhelm::Util::Tool->isNotIn("e", qw(a b c)));
ok(Eldhelm::Util::Tool->isNotIn("f", qw(a b c)));