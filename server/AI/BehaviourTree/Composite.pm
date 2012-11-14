package Eldhelm::AI::BehaviourTree::Composite;

use strict;
use Carp qw(longmess);

use base qw(Eldhelm::AI::BehaviourTree::Node);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->{index} = 0;

	return $self;
}

sub getUpdateList {
	my ($self) = @_;
	if (ref $self->{childs} ne "ARRAY") {
		$self->bTree->log(longmess "There is no valid 'childs' property in composite node $self");
		return [];
	}
	my @list = @{ $self->{childs} };
	return $self->{updateList} ||= [ @list[ $self->{index} .. $#list ] ];
}

sub nextChild {
	my ($self) = @_;
	my $list = $self->getUpdateList;
	return $self->getNodeObject($list->[ $self->{index}++ ]);
}

1;
