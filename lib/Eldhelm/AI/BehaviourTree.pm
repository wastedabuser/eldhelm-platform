package Eldhelm::AI::BehaviourTree;

use strict;

use parent 'Eldhelm::AI::AbstractThinker';

use Carp qw(longmess);
use Data::Dumper;
use Date::Format;
use Eldhelm::Util::Factory;

### UNIT TEST: 700_ai_bt.pl ###

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->loadDefinition($args{name}) if $args{name};

	return $self;
}

sub loadDefinition {
	my ($self, $name) = @_;
	$self->{definition} = $self->loadFile($name);
}

sub getNodeObject {
	my ($self, $def, %args) = @_;
	my $class = $def->{class};
	%args = (%$def, %args, bTree => $self);
	return Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Application::AI::BehaviourTree::$class", %args)
		if $class;

	my $type = $def->{type};
	unless ($type) {
		$self->log(longmess 'Can not determine node type for: '.Dumper($def));
		die;
	}
	return Eldhelm::Util::Factory->instance("Eldhelm::AI::BehaviourTree::$type", %args);
}

sub traverse {
	my ($self) = @_;
	$self->logStart();
	$self->log('Starting tree traversal');
	my $status = $self->{status} = $self->getNodeObject($self->{definition})->update;
	$self->log("Done tree traversal: $status");
}

sub evaluateProperty {
	my ($self, $value) = @_;
	return $value if ref $value || $value !~ /\$/;

	my $params  = $self->{params};
	my $context = $self->{context};
	$value =~ s/\$(\w+)/exists $params->{$1} ? "\$params->{$1}" : "\$context->$1()"/ge;
	my $ret = eval($value);
	$self->log(longmess $@) if $@;
	return $ret;
}

1;
