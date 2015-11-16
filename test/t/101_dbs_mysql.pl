use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Database::MySql;

diag('Default query');
my ($query, $params) = Eldhelm::Database::MySql->expandParams(qq|SELECT id
FROM
WHERE a = ? OR b = ? OR c = ?|,
	[
		1,2,3
	]
);

diag($query);
ok(index($query, 'a = ?') >= 0, 'not expanded 1');
ok(index($query, 'b = ?') >= 0, 'not expanded 2');
ok(index($query, 'c = ?') >= 0, 'not expanded 3');
ok(scalar(@$params) == 3, 'params remain');

diag('Expanding params');
my ($query, $params) = Eldhelm::Database::MySql->expandParams(qq|SELECT id
FROM
WHERE a IN (?) OR c = ? OR b IN (?)|,
	[
		[1,2,3,4],
		5,
		[6,7,8,9, 10],
	]
);

diag($query);
ok(index($query, 'a IN (?,?,?,?)') >= 0, 'expanded 1');
ok(index($query, 'b IN (?,?,?,?,?)') >= 0, 'expanded 2');
ok(index($query, 'c = ?') >= 0, 'not expanded 1');
ok(scalar(@$params) == 10, 'params merged');