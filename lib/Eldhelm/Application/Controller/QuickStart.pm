package Eldhelm::Application::Controller::QuickStart;

use strict;
use Data::Dumper;

use base qw(Eldhelm::Basic::Controller);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	my @list = qw(index);
	$self->export(@list);
	$self->public(@list);

	return $self;
}

sub index {
	my ($self) = @_;

	$self->responseWrite('I am Eldhelm::Application::Controller::QuickStart');
	$self->responseWrite('<br>');
	$self->responseWrite('Hello world!');
}

1;
