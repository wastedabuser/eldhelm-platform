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

my ($index, $configPath, $sourceContext, $className) = @ARGV;

unless ($className) {
	plan skip_all => 'This test can not run without a class context';
} else {
	plan 'no_plan';
}

my $config = do($configPath || '../../config.pl') or die 'Can not read config!';
my $worker = Eldhelm::Test::Mock::Worker->new(config => $config);

diag("Verifying construction");
my $controller = Eldhelm::Util::Factory->instance($className, router => $worker->{router});
my $source = Eldhelm::Util::FileSystem->getFileContents($sourceContext);

my %methods = %{ $controller->{exported} }, %{ $controller->{public} };
foreach (keys %methods) {
	ok($controller->can($_), "Public or exported method $_");
}
diag(Dumper [keys %methods]);

my @allResources;

diag("Verifying models");
my %models = map { +$_ => 1 } $source =~ /getModel\((.*?)\)/g;
foreach (keys %models) {
	my $val = eval("[$_]");
	next unless $val;

	my ($name, $args) = @$val;
	push @allResources, $name;
	eval {
		my $model = $controller->getModel($name, $args);
		ok($model, "Model $name ok");
	} or do {
		note($@);
		fail("Model $name is missing!");
	};
}

diag("Verifying views");
%models = map { +$_ => 1 } $source =~ /getView\((.*?)\)/g;
foreach (keys %models) {
	my $val = eval("[$_]");
	next unless $val;

	my ($name, $args) = @$val;
	$args ||= {};
	$args->{worker} = $worker;
	push @allResources, $name;
	eval {
		my $model = $controller->getView($name, $args);
		ok($model, "Views $name ok");
		1;
	} or do {
		note($@);
		fail("View $name is missing!");
	};
}

diag("Verifying controllers");
%models = map { +$_ => 1 } $source =~ /getController\((.*?)\)/g;
foreach (keys %models) {
	my $name = eval($_);
	next unless $name;

	push @allResources, $name;
	eval {
		my $model = $controller->getController($name);
		ok($model, "Views $name ok");
		1;
	} or do {
		note($@);
		fail("Controller $name is missing!");
	};
}

diag("Verifying scripts");
%models = map { +$_ => 1 } $source =~ /getScript\((.*?)\)/g;
foreach (keys %models) {
	my $name = eval($_);
	next unless $name;

	push @allResources, $name;
	eval {
		my $model = $controller->getScript($name);
		ok($model, "Scripts $name ok");
		1;
	} or do {
		note($@);
		fail("View $name is missing!");
	};
}

diag(Dumper \@allResources);
