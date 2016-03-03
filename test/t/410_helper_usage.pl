use strict;

use lib '..';
use lib '../..';
use lib '../../platform/lib';
use lib '../lib';
use lib '../../lib';

use Test::More;
use Data::Dumper;
use Eldhelm::Util::Factory;
use Eldhelm::Util::FileSystem;
use Eldhelm::Test::Mock::Worker;
use Eldhelm::Basic::View;

my ($index, $configPath, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do($configPath || '../../config.pl') or die 'Can not read config!';
my $worker = Eldhelm::Test::Mock::Worker->new(config => $config);

my $view = Eldhelm::Basic::View->new;
my $source = Eldhelm::Util::FileSystem->getFileContents($sourceContext);
ok(ref $view); # at least one valid test is needed, this one will pass

my @allResources;
diag("Verifying helpers");
my %views = map { +$_ => 1 } $source =~ /getHelper\(.*?(['"].*?['"])/gs;
foreach (keys %views) {
	my $name = eval($_);
	next unless $name;

	push @allResources, $name;
	eval {
		my $helper = $view->getHelper($name);
		ok($helper, "Helpers $name ok");
		1;
	} or do {
		note($@);
		fail("Helper $name is missing!");
	};
}

diag(Dumper \@allResources);