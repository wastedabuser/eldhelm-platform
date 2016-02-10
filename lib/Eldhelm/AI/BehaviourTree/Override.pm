package Eldhelm::AI::BehaviourTree::Override;

use strict;

use parent 'Eldhelm::AI::BehaviourTree::Decorator';

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub update {
	my ($self) = @_;
	$self->logUpdate;
	$self->getChild->update();
	my $status = $self->{status} ||= 'success';
	$self->logFinishUpdate;
	return $status;
}

1;
