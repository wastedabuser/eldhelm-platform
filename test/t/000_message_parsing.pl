use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";

use Eldhelm::Test::MainTester;
use Eldhelm::Test::SocketDummy;

my $server = Eldhelm::Test::MainTester->new(
	config => {
		server => {
			acceptProtocols   => [ "Http", "Json", "Xml", "System" ],
		},
	}
)->configure;
my $sock = Eldhelm::Test::SocketDummy->new;

$server->addToStream($sock, '-ping-');
ok(defined $server->{parsedData}, "seems to have parsed data");
is($server->{parsedData}{command}, "ping", "ping command received");