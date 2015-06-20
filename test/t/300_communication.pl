use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Util::Communication;

diag("test 1 - content");
my $response = Eldhelm::Util::Communication->loadUrl("http://eldhelm.com");
ok($response =~ /html/);

$response = Eldhelm::Util::Communication->loadUrl("http://eldhelm.com", { kiro => 1 });
ok($response =~ /html/);

$response = Eldhelm::Util::Communication->loadUrl("http://eldhelm.com", { kiro => 1 }, "get");
ok($response =~ /html/);

$response = Eldhelm::Util::Communication->loadUrl("http://eldhelm.com", { kiro => 1 }, "post");
ok($response =~ /html/);


diag("test 2 - json");
my $response = Eldhelm::Util::Communication->loadJson("http://eldhelm.com/servers.json");
ok(@$response > 0);
ok($response->[0]{host});

diag("test 3 - mask as browser");
my $response = Eldhelm::Util::Communication->simpleHttpRequest("http://eldhelm.com");
ok($response =~ /html/);

my $response = Eldhelm::Util::Communication->simpleHttpRequest("http://eldhelm.com", "post");
ok($response =~ /html/);
