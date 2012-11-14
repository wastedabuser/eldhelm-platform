package Eldhelm::AI::BehaviourTree::Selector;

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
		if ($childStatus eq "success") {
			$status = $childStatus;
			last;
		}
	}
	$self->{index} = 0 if $status ne "running";
	$self->{status} = $status ||= "failed";
	
	$self->logFinishUpdate;
	return $status
}

1;
