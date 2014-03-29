use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Helper::Html::Node;

diag("===============> test 1 - basic");

my $text = "Some text here to make a test";
my $pData = { id => 1234, kiro => "a" };

my $result = Eldhelm::Helper::Html::Node->compilePage(
	[   [ "div", $text ],
		[   "a", { href => "eldhelm.com/controller:market.facebook:resolveDispute?paymentId=$pData->{id}" },
			"resolve now"
		],
		[ "pre", Dumper($pData) ]
	]
);

note($result);

ok($result =~ /html/);
ok($result =~ /body/);
ok($result =~ /a href/);
ok($result =~ /pre/);
ok($result =~ /\$VAR/);
