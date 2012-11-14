package Eldhelm::AI::BehaviourTree::Inverter;

use strict;

use base qw(Eldhelm::AI::BehaviourTree::Decorator);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub update {
	my ($self) = @_;
	$self->logUpdate;
	my $status = $self->{status} = $self->getChild->update() ne "success" ? "success" : "failed";
	$self->logFinishUpdate;
	return $status;
}

1;
