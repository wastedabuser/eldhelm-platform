package Eldhelm::AI::BehaviourTree::Decorator;

use strict;

use base qw(Eldhelm::AI::BehaviourTree::Node);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub getChild {
	my ($self) = @_;
	return $self->getNodeObject($self->{child});
}

1;
