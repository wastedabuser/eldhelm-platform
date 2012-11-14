package Eldhelm::Basic::View;

use strict;
use Eldhelm::Server::Child;
use Eldhelm::Util::Factory;
use Eldhelm::Util::Template;
use Data::Dumper;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {
		data    => $args{data},
		worker  => Eldhelm::Server::Child->instance,
		tpl     => $args{tpl},
		tplArgs => $args{tplArgs} || {},
	};
	bless $self, $class;

	$self->init;

	return $self;
}

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

sub init {
	my ($self) = @_;
	$self->{$_} = $self->{worker}->getConfig("server.http.$_") foreach qw(documentRoot);
}

sub applyTemplate {
	my ($self, $name, $args) = @_;
	return Eldhelm::Util::Template->new(
		name   => $name,
		params => $args,
	)->compile;
}

sub compile {
	my ($self) = @_;
	return $self->applyTemplate($self->{tpl}, $self->{tplArgs});
}

sub getHelper {
	my ($self, $name, $args) = @_;
	$args ||= {};
	return Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Helper", $name, %$args);
}

sub addTplArgs {
	my ($self, $args) = @_;
	$self->{tplArgs} = { %{ $self->{tplArgs} }, %$args };
}

1;
