package Eldhelm::AI::NeuralNetwork::Neuron;

use strict;

use Carp qw(confess longmess);
use Data::Dumper;
use Eldhelm::AI::NeuralNetwork::TransferFunction;

my $eta   = .2;
my $alpha = .5;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->{value} = 1 if $self->{bias} && !$self->{value};
	$self->weightsFromList($args{weights}) if $args{weights};

	return $self;
}

sub value {
	my ($self, $val) = @_;
	if (defined $val) {
		$self->{value} = $val;
		return;
	}
	return $self->{value};
}

sub weightsFromList {
	my ($self, $list) = @_;
	$self->{_weights} ||= [];
	my $i = 0;
	foreach (@$list) {
		$self->{_weights}[ $i++ ]{value} = $_;
	}
}

sub generateWeights {
	my ($self, $ln) = @_;
	$self->{_weights} ||= [];
	foreach (0 .. $ln - 1) {
		$self->{_weights}[$_] = { value => rand() };
	}
}

sub weights {
	my ($self) = @_;
	return @{ $self->{_weights} };
}

sub weightValue {
	my ($self, $index) = @_;
	return $self->{_weights}[$index]{value};
}

sub weightDelta {
	my ($self, $index) = @_;
	return $self->{_weights}[$index]{delta};
}

sub updateWeight {
	my ($self, $index, $delta) = @_;
	my $w = $self->{_weights}[$index];
	$w->{delta} = $delta;
	$w->{value} += $delta;
}

sub connection {
	my ($self, $index) = @_;
	return $self->value * $self->weightValue($index);
}

sub transferFunction {
	my ($self, $value) = @_;
	return Eldhelm::AI::NeuralNetwork::TransferFunction->sigmoid($value);
}

sub transferFunctionDerivative {
	my ($self, $value) = @_;
	return Eldhelm::AI::NeuralNetwork::TransferFunction->sigmoidDerivative($value);
}

sub calculate {
	my ($self, $layer) = @_;
	my $sum   = 0;
	my $index = $self->{index};
	foreach my $n ($layer->neurons) {
		$sum += $n->connection($index);
	}
	$self->value($self->transferFunction($sum));
}

sub gradient {
	my ($self, $target) = @_;
	return $self->{gradient};
}

sub calculateOutputGradient {
	my ($self, $target) = @_;
	$self->{gradient} = ($target - $self->value) * $self->transferFunctionDerivative($self->value);
}

sub calculateHiddenGradient {
	my ($self, $nextLayer) = @_;
	$self->{gradient} = $self->sumDow($nextLayer) * $self->transferFunctionDerivative($self->value);
}

sub sumDow {
	my ($self, $layer) = @_;
	my $sum = 0;
	my $i   = 0;
	foreach my $n ($layer->neurons) {
		$sum += $self->weightValue($i++) * $n->gradient;
	}
	return $sum;
}

sub updateInputWeights {
	my ($self, $prevLayer) = @_;

	my $index = $self->{index};
	foreach my $n ($prevLayer->neurons) {
		$n->updateWeight($index, $eta * $n->value * $self->gradient + $alpha * $n->weightDelta($index));
	}
}

sub serialize {
	my ($self) = @_;
	return {
		weights => [ map $_->{value}, @{ $self->{_weights} } ],
		map { +$_ => $self->{$_} } grep { $self->{$_} } qw(bias)
	};
}

1;
