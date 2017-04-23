package Eldhelm::AI::NeuralNetwork::Layer;

use strict;

use Carp qw(confess longmess);
use Data::Dumper;
use Eldhelm::AI::NeuralNetwork::Neuron;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->createNeurons($args{neurons}) if $args{neurons};

	return $self;
}

sub createNeurons {
	my ($self, $neurons) = @_;

	$self->{_neurons} ||= [];
	my $i = 0;
	foreach (@$neurons) {
		push @{ $self->{_neurons} }, Eldhelm::AI::NeuralNetwork::Neuron->new(%$_, index => $i++);
	}
}

sub neurons {
	my ($self) = @_;
	return @{ $self->{_neurons} };
}

sub neuron {
	my ($self, $index) = @_;
	return $self->{_neurons}[ $index || 0 ];
}

sub numNeurons {
	my ($self) = @_;
	return scalar @{ $self->{_neurons} };
}

sub lastNeuron {
	my ($self) = @_;
	return $self->neuron($self->numNeurons - 1);
}

sub nonBiasNeurons {
	my ($self) = @_;
	return grep { !$_->{bias} } $self->neurons;
}

sub numNonBiasNeurons {
	my ($self) = @_;
	return scalar $self->nonBiasNeurons;
}

sub values {
	my ($self, $data) = @_;
	unless (defined $data) {
		return map $_->value(), $self->neurons;
	}
	my $i = 0;
	foreach my $n ($self->neurons) {
		$n->value($data->[ $i++ ]);
	}
}

sub propagateFromLayer {
	my ($self, $layer) = @_;
	foreach my $n ($self->neurons) {
		next if $n->{bias};
		$n->calculate($layer);
	}
}

sub serialize {
	my ($self) = @_;
	return { neurons => [ map { $_->serialize } $self->neurons ] };
}

1;
