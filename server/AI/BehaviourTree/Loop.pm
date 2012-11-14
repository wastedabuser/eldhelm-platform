package Eldhelm::AI::BehaviourTree::Loop;

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
	my ($rp, $status) = ($self->evaluateProperty($self->{repeat}));
	$self->logUpdate("$rp iterations");
	
	if ($rp < 0 || !$rp) {
		$self->{status} = $status = "failed";
		$self->logFinishUpdate;
		return $status;
	}
	
	my $node = $self->getChild;
	foreach (1 .. $rp) {
		$status = $node->update;
	}
	
	$self->{status} = $status ||= "success";
	$self->logFinishUpdate;
	return $status
}

1;