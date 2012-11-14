package Eldhelm::AI::BehaviourTree::Action;

use strict;
use Carp qw(longmess);

use base qw(Eldhelm::AI::BehaviourTree::Task);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub update {
	my ($self) = @_;

	$self->logUpdate;
	my $status = $self->{status} = $self->evaluateTask ? "success" : "failed";
	$self->logFinishUpdate;
	
	return $status;
}

1;
