package Eldhelm::Server::Handler::Xml;

=pod

=head1 NAME

Eldhelm::Server::Handler::Xml

=head1 DESCRIPTION

This class can't do much. The only thing it does is to provide the C<crossdomain.xml> file.

May be some day it will handle xml messages...

=head1 METHODS

=over

=cut

use strict;
use Data::Dumper;
use Carp;

use base qw(Eldhelm::Server::Handler);

# static methods

sub check {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	return $data =~ m/^<[a-z]+/i ? 1 : undef;
}

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;

	return (
		{   len           => -1,
			content       => $data,
			headerContent => ""
		},
		""
	);
}

# the class definition

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->init;

	return $self;
}

sub init {
	my ($self) = @_;
	$self->{$_} = $self->{worker}->getConfig("server.http.$_") foreach qw(documentRoot);
}

sub parseContent {
	my ($self, $data) = @_;
	if ($data =~ m|<([a-z_-]+)/>|) {
		$self->{command} = $1;
		$self->{file}    = $self->{worker}->getConfig("server.xml.$1");
		
		$self->worker->status("task", $self->{file});
		$self->{worker}->log("$self->{command}: $self->{file}", "access");
	}
}

sub respond {
	my ($self) = @_;
	my $cont;
	if ($self->{file}) {
		my $path = "$self->{documentRoot}/$self->{file}";
		$cont = $self->readDocument($path);
	}
	$self->worker->sendData("$cont\0");
}

sub finish {
	my ($self) = @_;
	$self->{worker}->endTask if $self->{file};
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
