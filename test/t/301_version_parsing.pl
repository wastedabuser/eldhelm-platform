use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Util::Version;

diag("test 1 - one number");

is(Eldhelm::Util::Version->parseVersion(1),    "0001");
is(Eldhelm::Util::Version->parseVersion("2"),  "0002");
is(Eldhelm::Util::Version->parseVersion("99"), "0099");

diag("test 2 - multiple numbers");

is(Eldhelm::Util::Version->parseVersion("1.2"),     "00010002");
is(Eldhelm::Util::Version->parseVersion("1.2.3"),   "000100020003");
is(Eldhelm::Util::Version->parseVersion("1.2.3.4"), "0001000200030004");
is(Eldhelm::Util::Version->parseVersion("1.2.3.4", 3), "000100020003");
is(Eldhelm::Util::Version->parseVersion("1",       3), "000100000000");

diag("test 3 - version compare");
is(Eldhelm::Util::Version->compare(1, 2), -1);
is(Eldhelm::Util::Version->compare(2, 1), 1);
is(Eldhelm::Util::Version->compare(1, 1), 0);

is(Eldhelm::Util::Version->compare("1.1", 1),     1);
is(Eldhelm::Util::Version->compare("1.1", "1.2"), -1);
is(Eldhelm::Util::Version->compare("2.1", "1.2"), 1);
is(Eldhelm::Util::Version->compare("1.2", "2.1"), -1);
is(Eldhelm::Util::Version->compare("1.1", "1.1"), 0);
