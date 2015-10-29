package Eldhelm::Basic::View;

=pod

=head1 NAME

Eldhelm::Basic::View - A basic view for creating a streamed output.

=head1 SYNOPSIS

You should not construct an object directly. You should instead use:

	Eldhelm::Basic::Controller->getView(undef, {
		# args
	});
	
Please see: L<< Eldhelm::Basic::Controller->getView >>

=head1 DESCRIPTION

This class provides compilation of a template against some data to cerate a streamed output.

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Server::Child;
use Eldhelm::Util::Factory;
use Eldhelm::Util::Template;
use Data::Dumper;
use Carp;

=item new(%args)

Constructs a new object.

C<%args> Hash - Contructor argumets;

C<data> HashRef - a custom data carried by the object;
C<tpl> String - dotted notation of a template template file in the Eldhelm::Application::Template namespace;
C<tplArgs> HashRef - compile arguments;

=cut

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

sub init {
	my ($self) = @_;
	$self->{$_} = $self->{worker}->getConfig("server.http.$_") foreach qw(documentRoot);
}

=item worker() Eldhelm::Server::Worker

Returns the current worker thread wrapper class.

=cut

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

=item applyTemplate() String

Applys arguments to a template and returns the compiled output.

C<$name> String - a dotted notation pointing to a template file in the Eldhelm::Application::Template namespace;
C<$args> HashRef - the teplate compile arguments;

=cut

sub applyTemplate {
	my ($self, $name, $args) = @_;
	return Eldhelm::Util::Template->new(
		name   => $name,
		params => $args,
	)->compile;
}

=item compile() String

Compiles the current view

=cut

sub compile {
	my ($self) = @_;
	return $self->applyTemplate($self->{tpl}, $self->{tplArgs});
}

=item getHelper($name, $args) Eldhelm::Helper

Returns a helper object by name.

C<$name> String - a dotted notation poiting to a class in the Eldhelm::Helper namespace;
C<$args> HashRef - arguments passed to the helper constructor;

=cut

sub getHelper {
	my ($self, $name, $args) = @_;
	$args ||= {};
	return Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Helper", $name, %$args);
}

=item addTplArgs($args)

Appedns additional compile arguments to the view;

C<$args> HashRef - compile arguments;

=cut

sub addTplArgs {
	my ($self, $args) = @_;
	$self->{tplArgs} = { %{ $self->{tplArgs} }, %$args };
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
