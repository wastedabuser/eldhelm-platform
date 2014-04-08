use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Database::Template;

my $tpl = Eldhelm::Database::Template->new(doNotUseDesc => 1, ignoreUndefAlias => 1);

diag("===============> test 1 - basic");

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
ok($query =~ /t1.c/);
ok($query !~ /t1.b/);
ok($query !~ /t1.d/);
ok($query =~ /c\s?=\s?1/);

diag("===============> test 2 - test function parsing");

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

diag("===============> test 3 - filters with palceholders");

$tpl->stream("SELECT
		t1.a,
	FROM table1 t1
	WHERE 
		a = 1 [fltr1 AND b = ?]
");

$query = $tpl->compile;

note($query);
ok($query !~ /b\s?=/);

diag("===============> test 4 - for prepared statements palceholders");

$tpl->stream("SELECT
		t1.a
	FROM table1 t1
	WHERE 
		a = ?
");
$query = $tpl->compile;

note($query);
ok($query =~ /\?/);

diag("===============> test 5 - for aggregator with star");

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

diag("===============> test 6 - more complex query");

$tpl->stream("SELECT 
	u.id,
	u.first_name,
	u.last_name,
	u.name,
	u.mail,
	u.secret_id
FROM 
	user u LEFT JOIN reminder_gift rg ON rg.user_id = u.id AND rg.type IN ('remind', 'premium')
WHERE 
	u.mail_valid = 1 AND registered_on > DATE_SUB(CURDATE(), INTERVAL 4 MONTH) AND 
	survey_result = 'yes' AND active = 1 AND u.mail_notify_gifts = 1 AND rg.user_id IS NULL AND
	(SELECT COUNT(*) FROM hero WHERE user_id = u.id AND level > 20) > 0 AND
	(SELECT created_on FROM `session` WHERE user_id = u.id ORDER BY created_on DESC LIMIT 1) < DATE_SUB(CURDATE(), INTERVAL 14 DAY)
LIMIT 100");

$query = $tpl->clearFields->compile;
note($query);
ok($query =~ /\(\s*\*\s*\)/);
ok($query =~ /'yes'/);
ok($query =~ /'remind'/);
ok($query =~ /'premium'/);

diag("===============> test 6 - more complex query");

$tpl->stream("SELECT 
	DATE(created_on) AS x, 
	SUM(gr.gold) AS y 
FROM 
	`purchase` p, `service` s, `hero_gamble_reward` gr
WHERE 
	p.service_id = s.id AND gr.purchase_id = p.id AND gr.gold > '0' AND
	DATE(p.created_on) >= DATE_SUB(CURDATE(), INTERVAL {months} MONTH) AND s.code = 'gamble'
	[user AND p.user_id = ?]
GROUP BY x
ORDER BY created_on");

$query = $tpl->clearFields->compile;
note($query);
ok($query !~ /h\.user_id/);

diag("===============> test 7 - doble filter test");

$tpl->stream("SELECT 
	DATE(hs.created_on) AS x, 
	COUNT(*) AS y 
FROM `hero_skill` hs, hero h
WHERE h.id = hs.hero_id AND
	DATE(hs.created_on) >= DATE_SUB(CURDATE(), INTERVAL {months} MONTH)
	[user AND h.user_id = ?]
	[upgraded AND hs.created_on <> hs.started_on]
	AND hs.skill_id = ?
GROUP BY x
ORDER BY hs.created_on");

$query = $tpl->clearFields->clearFilter->compile({ filter => { user => 1 }, placeholders => { months => 12 } });
note($query);
ok($query =~ /h\.user_id/);
ok($query !~ /hs\.started_on/);

diag("===============> test 8 - only custom filter in where clause");

$tpl->stream("SELECT
	s.id, 
	s.name
FROM skill s
WHERE [common s.race_id IS NULL AND s.class_id IS NULL AND s.character_id IS NULL]");

$query = $tpl->clearFields->clearFilter->compile;
note($query);
ok($query !~ /s\.race_id/);

$query = $tpl->clearFields->clearFilter->compile({ filter => { common => 1 } });
note($query);
ok($query =~ /s\.race_id/);

diag("===============> test 9 - parsing != operator");

$tpl->stream("SELECT 
	DATE(u.created_on) AS x, 
	COUNT(*) AS y 
FROM 
	`user` u 
WHERE 
	DATE(u.created_on) >= DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL {period} MONTH) AND 
	(u.created_on != u.registered_on OR u.registered_on IS NULL) AND u.active = 1 
GROUP BY x 
ORDER BY x");

$query = $tpl->clearFields->clearFilter->compile;
note($query);
ok($query =~ /!=/);

diag("===============> test 10 - pasing grouped tables in from and joins");

$tpl->stream("SELECT
		t1.a,
	FROM (table1 t1, table2 t2)
	WHERE 
		a = 1
");
$query = $tpl->clearFields->clearFilter->clearTableAliases->compile;
note($query);
note(Dumper $tpl->{tableAliases});
ok(keys %{ $tpl->{tableAliases}} == 2);
ok($tpl->{tableAliases}{t1});
ok($tpl->{tableAliases}{t2});

$tpl->stream("SELECT
		t1.a,
	FROM 
		(table1 AS t1, table2 AS t2)
		LEFT JOIN table3 AS t3 ON (kiro1 = 1 AND pesho1 = 2)
	WHERE 
		a = 1
");
$query = $tpl->clearFields->clearFilter->clearTableAliases->compile;
note($query);
note(Dumper $tpl->{tableAliases});
ok(keys %{ $tpl->{tableAliases}} == 3);
ok($tpl->{tableAliases}{t1});
ok($tpl->{tableAliases}{t2});
ok($tpl->{tableAliases}{t3});

$tpl->stream("SELECT
		t1.a,
	FROM 
		table1 t1, table2 t2
		LEFT JOIN table3 t3 ON (kiro1 = 1 AND pesho1 = 2)
		LEFT JOIN table4 t4 ON (kiro2 = 1 AND pesho2 = 2)
	WHERE 
		a = 1
");
$query = $tpl->clearFields->clearFilter->clearTableAliases->compile;
note($query);
note(Dumper $tpl->{tableAliases});
ok(keys %{ $tpl->{tableAliases}} == 4);
ok($tpl->{tableAliases}{t1});
ok($tpl->{tableAliases}{t2});
ok($tpl->{tableAliases}{t3});
ok($tpl->{tableAliases}{t4});

diag("===============> test 11 - pasing subquery in FROM");

$tpl->stream("SELECT 
	DATE_FORMAT(t.start_date, '{aggregation}') battle_date,
	COUNT(*) AS wins,
	(SELECT character_id FROM hero WHERE id = bp.hero_id) AS character_id
FROM 
	(SELECT b.id, b.start_date FROM battle b 
		WHERE DATE(b.start_date) >= DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL {period} MONTH) 
		AND total_turns > 0 AND game_type IN ('challenge', 'rank', 'tournament')) as tsubq,
	battle_player as bp
WHERE 
	bp.battle_id = t.id
GROUP BY battle_date, character_id
ORDER BY battle_date, wins");
$query = $tpl->clearFields->clearFilter->clearTableAliases->compile({ filter => { win => 1 } });
note($query);
note(Dumper $tpl->{tableDesc});
note(Dumper $tpl->{tableAliases});
ok(!$tpl->{tableDesc}{as});
ok(!$tpl->{tableDesc}{id});
ok(!$tpl->{tableDesc}{start_date});