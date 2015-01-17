package Eldhelm::Server::Handler::Xml;

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
	my $self = Eldhelm::Server::Handler->new(%args);
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

1;
