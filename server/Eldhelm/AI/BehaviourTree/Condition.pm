package Eldhelm::AI::BehaviourTree::Condition;

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
	
	my ($ret, $status);

	if ($self->{test}) {
		$self->logUpdate($self->{test});
		$ret = $self->evaluateProperty($self->{test});
	} else {
		$self->logUpdate;
		$ret = $self->evaluateTask;
	}

	$status = $self->{status} = $ret ? "success" : "failed";
	$self->logFinishUpdate;

	return $status;
}

1;
