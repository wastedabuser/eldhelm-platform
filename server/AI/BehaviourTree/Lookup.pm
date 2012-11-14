package Eldhelm::AI::BehaviourTree::Lookup;

use strict;

use base qw(Eldhelm::AI::BehaviourTree::Decorator);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub loadDefinition {
	my ($self, $name) = @_;
	return $self->{definition} = $self->bTree->loadFile($name);
}

sub update {
	my ($self) = @_;
	$self->logUpdate($self->{value});

	my $status;
	my $def = $self->loadDefinition($self->{value});
	if ($def) {
		my $node = $self->getNodeObject($def);
		$status = $node->update;
	} else {
		$status = "failed";
	}

	$self->{status} = $status;
	$self->logFinishUpdate;
	return $status;
}

1;
