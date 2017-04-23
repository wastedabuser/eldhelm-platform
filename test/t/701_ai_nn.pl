use strict;
use lib '../lib';
use lib '../../lib';
use Test::More 'no_plan';
use Data::Dumper;
use Eldhelm::AI::NeuralNetwork;

diag('NN creation');
my $nn = Eldhelm::AI::NeuralNetwork->new(
	definition => [
		{ neurons => [ { weights => [2] }, { value => 1, weights => [2], bias => 1 } ] },
		{ neurons => [ { weights => [3] }, { value => 1, weights => [3], bias => 1 } ] },
		{ neurons => [ {} ] }
	]
);
is(scalar($nn->layers),       3);
is(scalar($nn->hiddenLayers), 1);
is($nn->numLayers,            3);

foreach (0 .. 1) {
	is(scalar($nn->layer($_)->neurons), 2);
}
is(scalar($nn->lastLayer->neurons), 1);

diag('NN basic propagation');
my $output = $nn->traverse([10]);
is($nn->layer->neuron->value,   10);
is([ $nn->layer->values ]->[0], 10);
foreach (1 .. 2) {
	ok($nn->layer($_)->neuron->value > 0);
}
ok($output->[0] > 0);

diag('NN bias neurons unchanged');
foreach (0 .. 1) {
	is($nn->layer($_)->lastNeuron->value, 1);
}

diag('NN training');
$nn->train([10], [100]);
ok($nn->{error} > 0);
foreach my $l ($nn->hiddenLayers, $nn->lastLayer) {
	foreach my $n ($l->neurons) {
		ok($n->gradient > 0);
	}
}

diag('NN generate weigths');
$nn =
	Eldhelm::AI::NeuralNetwork->new(
	definition => [ { neurons => [ {}, {}, { bias => 1} ] }, { neurons => [ {}, {}, { bias => 1} ] }, { neurons => [ {}, {} ] } ]);

$nn->generateWeights;
foreach my $l ($nn->layer, $nn->hiddenLayers) {
	foreach my $n ($l->neurons) {
		ok(scalar($n->weights) == 2);
		ok($n->weightValue(0) > 0);
		ok($n->weightValue(1) > 0);
	}
}

diag('NN serialization');
my $data = $nn->serialize;
# diag(Dumper $data);
is(scalar @$data, 3);
my @list = @$data;
pop @list;
foreach my $l (@list) {
	is(scalar @{ $l->{neurons} }, 3);
	foreach my $n (@{ $l->{neurons} }) {
		is(scalar @{ $n->{weights} }, 2);
	}
}
