use strict;
use lib '../lib';
use lib '../../lib';
use Test::More 'no_plan';
use Data::Dumper;
use Eldhelm::AI::BehaviourTree;

diag('BT creation');
my $bt = Eldhelm::AI::BehaviourTree->new(
logEnabled => 1,
	params => {
		var1 => 1,
		var2 => 2,
		var3 => 3
	},
	definition => {
		type   => 'Sequence',
		childs => [
			{   type => 'Condition',
				test => '$var1 == 1',
			},
			{   type => 'Condition',
				test => '$var2 == 2',
			},
			{   type => 'Condition',
				test => '$var3 == 3',
			}
		]
	}
);

diag('BT traversing');
$bt->traverse;

is($bt->{status}, 'success');