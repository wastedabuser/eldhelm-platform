package Eldhelm::AI::NeuralNetwork::TransferFunction;

use strict;

sub sigmoid {
	my ($self, $val) = @_;
	return 1.0 / (1.0 + exp($val));
}

sub sigmoidDerivative {
	my ($self, $val) = @_;
	my $f = 1.0 / (1.0 + exp($val));
	return $f * (1 - $f);
}

1;
