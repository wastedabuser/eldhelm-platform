package Eldhelm::AI::BehaviourTree::Task;

use strict;
use Carp qw(longmess);

use base qw(Eldhelm::AI::BehaviourTree::Node);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub evaluateTask {
	my ($self)  = @_;
	my $context = $self->bTree->{context};
	my $fn      = $self->{value};
	my $ar      = $self->{args};
	my @args = ref $ar ? @$ar : ();
	my ($ret, $status);

	eval {
		$ret = $context->$fn(map { $self->evaluateProperty($_) } @args);
	};
	if ($@) {
		$self->bTree->log(longmess $@);
	}

	return $ret && !$@;
}

sub logUpdate {
	my ($self, $name) = @_;
	return $self->SUPER::logUpdate($name) if $name;
	
	my @args = ref $self->{args} ? @{ $self->{args} } : ();
	return $self->SUPER::logUpdate("$self->{value} (".join(", ", @args).")");
}

1;
