package Eldhelm::AI::BehaviourTree::End;

use strict;

use base qw(Eldhelm::AI::BehaviourTree::Node);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;
	
	return $self;
}

sub update {
	my ($self) = @_;
	my $status = $self->{status} ||= "failed";
	$self->logFinishUpdate;
	return $status;
}

1;