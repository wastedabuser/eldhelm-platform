use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Database::Template;

my $tpl = Eldhelm::Database::Template->new;

diag("test 1 - basic");

$tpl->stream("SELECT
		t1.a,
		t1.b,
		t1.c,
		t1.d
	FROM `table1` AS t1
	WHERE 
		a = 1 AND b = 2 AND c = {plc1}
");

$tpl->placeholders({ plc1 => 1 });

my $query = $tpl->compile({
	fields => ["a", "c"],
});

ok($query);
note($query);
ok($query =~ /t1.a/);
ok($query !~ /t1.b/);

diag("test 2 - test function parsing");

$tpl->stream("SELECT
		t1.a,
	FROM table1 t1
	WHERE 
		a = curdate() and ( a = 1 )
");

$query = $tpl->compile({
	fields => ["a"],
});

ok($query =~ /curdate\(/);
note($query);

diag("test 3 - filters with palceholders");

$tpl->stream("SELECT
		t1.a,
	FROM table1 t1
	WHERE 
		a = 1 [fltr1 AND b = ?]
");

$query = $tpl->compile;

note($query);
ok($query !~ /b =/);

diag("test 4 - for prepared statements palceholders");

$tpl->stream("SELECT
		t1.a
	FROM table1 t1
	WHERE 
		a = ?
");
$query = $tpl->compile;

note($query);
ok($query =~ /\?/);

diag("test 5 - for aggregator with star");

$tpl->stream("SELECT
		count(*) as uga
	FROM table1 t1
	WHERE 
		a = ?
");
$query = $tpl->compile();
ok($query !~ /\*/);
note($query);

$query = $tpl->compile({ fields => ["uga"] });
ok($query =~ /\*/);
note($query);

