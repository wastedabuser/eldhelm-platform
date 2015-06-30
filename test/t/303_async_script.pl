use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Util::AsyncScript;
use MIME::Base64 qw(encode_base64 decode_base64);

my ($a1, $a2);
{
	local $Data::Dumper::Terse = 1;
	$a1 = encode_base64(Dumper([ { a => 5 }, { b => 10 }, { c => 15 } ]), "");
	$a2 = encode_base64(Dumper({ a => 1, b => 2 }), "");
}

ok($a1, "has some input");
ok($a2, "has some input");

diag("parse argv");
my ($pa1) = Eldhelm::Util::AsyncScript->parseArg($a1);
is(ref($pa1), "ARRAY", "param");

diag("test argv");
my ($p1, $p2) = Eldhelm::Util::AsyncScript->argv($a1, $a2);

note($p1);
is(ref($p1), "ARRAY", "param 1");
is($p1->[1]{b}, 10);
is($p1->[2]{c}, 15);

note($p2);
is(ref($p2), "HASH", "param 2");
is($p2->{a}, 1);
is($p2->{b}, 2);
