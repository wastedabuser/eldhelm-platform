use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Carp;

use Eldhelm::Test::Fixture::TestBench;
use Eldhelm::Test::Mock::Router;
use Eldhelm::Server::Handler::Json;

my $result;
my $tester = Eldhelm::Test::Fixture::TestBench->new(
	router => Eldhelm::Test::Mock::Router->new(
		callback => sub {
			my ($headers, $data) = @_;
			$result = $data->{result};
			note("Callback: $result");
		}
	),
	config => {}
);
my $handler = Eldhelm::Server::Handler::Json->new(
	worker	=> $tester->worker,
	connection => $tester->connection
);

diag("test 0 - init message sequence");
$handler->{json} = { result => "go1" };
$handler->{headers} = { id => 1 };
$handler->acceptMessage;
is($result, "go1");

diag("test 1 - random order messages");
$handler->{json} = { result => "go3" };
$handler->{headers} = { id => 3 };
$handler->acceptMessage;
is($result, "go1");

$handler->{json} = { result => "go5" };
$handler->{headers} = { id => 5 };
$handler->acceptMessage;
is($result, "go1");

$handler->{json} = { result => "go4" };
$handler->{headers} = { id => 4 };
$handler->acceptMessage;
is($result, "go1");

$handler->{json} = { result => "go2" };
$handler->{headers} = { id => 2 };
$handler->acceptMessage;
is($result, "go5");

diag("test 2 - message with no id");
$handler->{json} = { result => "go0" };
$handler->{headers} = {};
$handler->acceptMessage;
is($result, "go5");

diag("test 3 - repeat message");
foreach (2, 4, 3, 1, 5) {
	$handler->{json} = { result => "second go$_" };
	$handler->{headers} = { id => $_ };
	$handler->acceptMessage;
	is($result, "go5", "repeat message $_");
}

diag("test 4 - normal valid message");
$handler->{json} = { result => "go6" };
$handler->{headers} = { id => 6 };
$handler->acceptMessage;
is($result, "go6");

diag("test 5 - without session");
delete $handler->{session};
delete $tester->connection->{session};
$handler->{json} = { result => "go100" };
$handler->{headers} = { id => 100 };
$handler->acceptMessage;
is($result, "go100");
