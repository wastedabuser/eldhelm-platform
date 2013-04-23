use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Test::Fixture::MainTester;
use Eldhelm::Test::Mock::Socket;

my $server = Eldhelm::Test::Fixture::MainTester->new(
	config => {
		server => {
			acceptProtocols   => [ "Http", "Json", "Xml", "System" ],
		},
	},
)->configure;
my $sock = Eldhelm::Test::Mock::Socket->new(1);
my $sock2 = Eldhelm::Test::Mock::Socket->new(2);

$server->addToStream($sock, '-ping-');
my $data = $server->getNextParsed;

diag("test 1");

ok(defined $data);
is($data->{command}, "ping");

diag("test 2");

$server->addToStream($sock, '-ping--echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":"9"}]{"a":"1"}-ping-');

is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");
$data = $server->getNextParsed;
is($data->{headers}{type}, "deviceInfo");
is($server->getNextParsed->{command}, "ping");

diag("test 3");

$server->addToStream($sock, '-pin');
$server->addToStream($sock, 'g--ech');
$server->addToStream($sock, 'o-["eldhlem-json-1.1",');
$server->addToStream($sock, '{"type":"deviceInfo","conten');
$server->addToStream($sock, 'tLength":"9"}]{"a":"1"}-pi');
$server->addToStream($sock, 'ng-');

is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");
$data = $server->getNextParsed;
is($data->{headers}{type}, "deviceInfo");
is($server->getNextParsed->{command}, "ping");

diag("test 4.1");
$server->addToStream($sock, '["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":"14"}]{"a":');
$server->addToStream($sock, '"12');
$server->addToStream($sock, '3456"}');

$data = $server->getNextParsed;
is($data->{headers}{type}, "deviceInfo");

diag("test 4.2");
is($server->parsedCound, 0);

$server->addToStream($sock, '-ping--echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":"14"}]{"a":');
$server->addToStream($sock, '"123');
$server->addToStream($sock, '456"}-ping-');

is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");

$data = $server->getNextParsed;
is($data->{headers}{type}, "deviceInfo");
is($server->getNextParsed->{command}, "ping");

diag("test 4.3");
is($server->parsedCound, 0);

$server->addToStream($sock, '-ping--echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":"14"}]{"a":');
$server->addToStream($sock, '"123');
$server->addToStream($sock, '456"}-ping-["eldhlem-json-1.1",{"contentLength":"14","c":"1"}]{"b":"654321"}-ping-');
$server->addToStream($sock, '["eldh');
$server->addToStream($sock, 'lem-json-1.1",{"contentL');
$server->addToStream($sock, 'ength":"12","d":"1"}]{"c":"1234"}["eldhlem-jso');
$server->addToStream($sock, 'n-1.1",{"contentLength":"1');
$server->addToStream($sock, '3","e":"1"}]{"d":"12345"}');

is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");

$data = $server->getNextParsed;
is($data->{headers}{type}, "deviceInfo");
is($server->getNextParsed->{command}, "ping");

$data = $server->getNextParsed;
is($data->{headers}{c}, 1);
is($server->getNextParsed->{command}, "ping");

$data = $server->getNextParsed;
is($data->{headers}{d}, 1);

$data = $server->getNextParsed;
is($data->{headers}{e}, 1);

diag("test 5.1");

$server->addToStream($sock, '-ping--');
$server->addToStream($sock, 'echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");
is($server->getNextParsed->{headers}{contentLength}, "2");

diag("test 5.2");
is($server->parsedCound, 0);

$server->addToStream($sock, '-ping--');
$server->addToStream($sock, 'echo-["eldhlem-');
$server->addToStream($sock, 'json-1.1",{"contentLength":2,"type":"deviceInfo"}]{}');
is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");
is($server->getNextParsed->{headers}{contentLength}, "2");

diag("test 5.3");

$server->addToStream($sock, 'echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
ok(!defined $server->getNextParsed);
$server->addToStream($sock, '-ping-');
is($server->getNextParsed->{command}, "ping");

diag("test 5.4");

$server->addToStream($sock, '--echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
ok(!defined $server->getNextParsed);
$server->addToStream($sock, '-ping-');
is($server->getNextParsed->{command}, "ping");

diag("test 5.5");

$server->addToStream($sock, '-');
$server->addToStream($sock, 'echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
is($server->getNextParsed->{command}, "echo");
is($server->getNextParsed->{headers}{contentLength}, "2");

diag("test 5.6");

$server->addToStream($sock, '-');
$server->addToStream($sock, 'p');
$server->addToStream($sock, 'i');
$server->addToStream($sock, 'n');
$server->addToStream($sock, 'g');
$server->addToStream($sock, '-');
$server->addToStream($sock, '-');
$server->addToStream($sock, 'echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");
is($server->getNextParsed->{headers}{contentLength}, "2");

diag("test 5.7");

$server->addToStream($sock, '-');
$server->addToStream($sock, 'echo-["eldhlem');
$server->addToStream($sock, '-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
is($server->getNextParsed->{command}, "echo");
is($server->getNextParsed->{headers}{contentLength}, "2");

diag("test 5.8");

$server->addToStream($sock, '-');
$server->addToStream($sock, 'echo');
$server->addToStream($sock, '-["eldhlem-');
$server->addToStream($sock, 'json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
is($server->getNextParsed->{command}, "echo");
is($server->getNextParsed->{headers}{contentLength}, "2");


diag("test 6");

$server->addToStream($sock, '-');
$server->addToStream($sock, 'echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":14}]{"a":"');
$server->addToStream($sock, '-ping-"}-echo-');
is($server->getNextParsed->{command}, "echo");
$data = $server->getNextParsed;
is($data->{headers}{type}, "deviceInfo");
is($server->getNextParsed->{command}, "echo");

diag("test 7.1");

$server->clearErrors;
$server->addToStream($sock, '-ping---echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
is($server->getNextParsed->{command}, "ping");
ok(!defined $server->getNextParsed);
$server->addToStream($sock, '-ping-');
is($server->getNextParsed->{command}, "ping");
note(Dumper $server->{parsedErrors});

diag("test 7.2");

$server->clearErrors;
$server->addToStream($sock, '-ping---echo-["eldhlem-json-1.1",{"type":"deviceInfo","contentLength":2}]{}');
$server->addToStream($sock2, '-echo---ping-');
is($server->getNextParsed->{command}, "ping");
is($server->getNextParsed->{command}, "echo");
note(Dumper $server->{parsedErrors});

