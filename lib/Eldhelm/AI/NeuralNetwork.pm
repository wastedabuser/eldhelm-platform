package Eldhelm::AI::NeuralNetwork;

use strict;

use parent 'Eldhelm::AI::AbstractThinker';

use Data::Dumper;
use Eldhelm::Util::FileSystem;
use Eldhelm::AI::NeuralNetwork::Layer;

### UNIT TEST: 701_ai_nn.pl ###

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->loadDefinition($args{name}) if $args{name};
	$self->createLayers($self->{definition}) if $self->{definition};

	return $self;
}

sub createLayers {
	my ($self, $layers) = @_;

	$self->{_layers} ||= [];
	foreach (@$layers) {
		push @{ $self->{_layers} }, Eldhelm::AI::NeuralNetwork::Layer->new(%$_);
	}
}

sub layers {
	my ($self) = @_;
	return @{ $self->{_layers} };
}

sub layer {
	my ($self, $index) = @_;
	return $self->{_layers}[ $index || 0 ];
}

sub numLayers {
	my ($self) = @_;
	return scalar @{ $self->{_layers} };
}

sub lastLayer {
	my ($self) = @_;
	return $self->layer($self->numLayers - 1);
}

sub hiddenLayers {
	my ($self) = @_;
	my @list = $self->layers;
	shift @list;
	pop @list;
	return @list;
}

sub generateWeights {
	my ($self) = @_;
	my $nl;
	foreach my $l (reverse $self->layers) {
		if ($nl) {
			my $nbln = scalar $nl->nonBiasNeurons;
			foreach my $n ($l->neurons) {
				$n->generateWeights($nbln);
			}
		}
		$nl = $l;
	}
}

sub traverse {
	my ($self, $data) = @_;
	$self->logStart();
	return $self->{output} = $self->results($data);
}

sub results {
	my ($self, $data) = @_;
	$self->layer->values($data);
	$self->propagate;
	return [ $self->lastLayer->values ];
}

sub propagate {
	my ($self) = @_;
	my ($prev, @layers) = $self->layers;
	foreach my $l (@layers) {
		$l->propagateFromLayer($prev);
		$prev = $l;
	}
}

sub rms {
	my ($self, $data, $target) = @_;
	my $err = 0;
	my $ln  = scalar @$data;
	for (my $i = 0 ; $i < $ln ; $i++) {
		$err += ($target->[$i] - $data->[$i])**2;
	}
	$err /= $ln;
	return sqrt $err;
}

sub train {
	my ($self, $input, $output) = @_;
	$self->{error} = $self->rms($self->results($input), $output);
	my $i = 0;
	foreach ($self->lastLayer->neurons) {
		$_->calculateOutputGradient($output->[ $i++ ]);
	}
	my @layers = $self->layers;
	for ($i = $#layers - 1 ; $i > 0 ; $i--) {
		foreach ($layers[$i]->neurons) {
			$_->calculateHiddenGradient($layers[ $i + 1 ]);
		}
	}
	for ($i = $#layers ; $i > 0 ; $i--) {
		foreach ($layers[$i]->neurons) {
			$_->updateInputWeights($layers[ $i - 1 ]);
		}
	}
}

sub trainCsv {
	my ($self, $path, $sep) = @_;
	$sep ||= ',';
	my $lines = Eldhelm::Util::FileSystem->getFileContentsLines($path);
	my $nl    = $self->layer->numNonBiasNeurons;
	$self->log('Processing '.scalar(@$lines).' lines');
	my $pln = 5000;
	my $num = 1;
	foreach my $l (@$lines) {
		$l =~ s/[\n\r]+$//;
		my @columns = split /$sep/, $l;
		my $input = [ @columns[ 0 .. $nl - 1 ] ];
		my $output = [ @columns[ $nl .. $#columns ] ];
		unless($num % $pln) {
			$self->log("Training $num:");
			$self->log('  Input  '.join '; ', @$input);
			$self->log('  Output '.join '; ', @$output);
		}
		$self->train($input, $output);
		$self->log("Done $num; ERROR $self->{error};") unless $num % $pln;
		$num++;
	}
	$self->log('Done!');
}

sub serialize {
	my ($self) = @_;
	return [ map { $_->serialize } $self->layers ];
}

sub serializeString {
	my ($self) = @_;
	my $data = $self->serialize;
	local $Data::Dumper::Sparseseen = 1;    # no seen structure
	local $Data::Dumper::Terse      = 1;    # no '$VAR1 = '
	return Dumper $data;
}

1;
