package Eldhelm::AI::BehaviourTree::Node;

use strict;
use Carp qw(longmess);

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->{level} ||= 0;
	
	return $self;
}

sub getNodeObject {
	my ($self, $def) = @_;
	return if !ref $def;
	return $self->bTree->getNodeObject($def, parent => $self, level => $self->{level} + 1);
}

sub status {
	my ($self) = @_;
	return $self->{status};
}

sub bTree {
	my ($self) = @_;
	return $self->{bTree};
}

sub logUpdate {
	my ($self, $more) = @_;
	$self->bTree->log(("|" x $self->{level})."- Updating node $self->{type}".($more ? ": $more" : ""));
}

sub logFinishUpdate {
	my ($self) = @_;
	$self->bTree->log(("|" x $self->{level})."- Done updating node $self->{type}: $self->{status}");
}

sub evaluateProperty {
	my ($self, $value) = @_;
	return $self->bTree->evaluateProperty($value);
}

1;
