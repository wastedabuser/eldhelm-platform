use strict;
use lib "../lib";
use lib "../../lib";
use Test::More "no_plan";
use Data::Dumper;
use Eldhelm::Test::Mock::Worker;
use MIME::Base64 qw(encode_base64 decode_base64);


my $worker = Eldhelm::Test::Mock::Worker->new(
	config => {
		server => {
			serverHome => ".."
		}
	}
);
$worker->{configPath} = "config_path_here";

$worker->runExternalScript("non_existing_test_external_script");
my $log = $worker->getLastLogEntry("error");
ok($log =~ /non_existing_test_external_script/, "error ok");

my $result = $worker->runExternalScript("test_external_script", { some_data_here => { deeply => "I have data!" } });
$log = $worker->getLastLogEntry("access");
ok($log =~ /test_external_script/, "access ok");