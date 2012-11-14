package Eldhelm::AI::BehaviourTree::Sequence;

use strict;

use base qw(Eldhelm::AI::BehaviourTree::Composite);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub update {
	my ($self) = @_;
	$self->logUpdate;
	
	my ($status, $child, $childStatus);
	while ($child = $self->nextChild) {
		$childStatus = $child->update;
		if ($childStatus ne "success") {
			$status = $childStatus;
			last;
		}
	}
	$self->{index} = 0 if $status ne "running";
	$self->{status} = $status ||= "success";
	
	$self->logFinishUpdate;
	return $status
}

1;
