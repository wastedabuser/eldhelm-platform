package Eldhelm::Test::Mock::Worker;

use strict;

use threads;
use threads::shared;
use Data::Dumper;
use Eldhelm::Test::Mock::Session;
use Carp qw(confess longmess);

use parent 'Eldhelm::Server::Child';

sub create {
	my (%args) = @_;
	Eldhelm::Server::Worker->new(%args);
}

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Child->instance;
	if (ref $self ne 'Eldhelm::Server::Worker') {
		$self = Eldhelm::Server::Child->new(%args);
		bless $self, $class;

		$self->addInstance;

		$self->{config}         = is_shared($args{config}) ? $args{config} : shared_clone($args{config} || {});
		$self->{persists}       = shared_clone({});
		$self->{persistsByType} = shared_clone({});
		$self->{persistLookup}  = shared_clone({});
		$self->{log}            = [];
		$self->{debug}          = [];
		$self->{error}          = [];
		$self->{access}         = [];
	}
	return $self;
}

sub log {
	my ($self, $msg) = @_;
	push @{ $self->{log} }, $msg;
	warn "# general log: $msg";
}

sub debug {
	my ($self, $msg) = @_;
	push @{ $self->{debug} }, $msg;
	warn "# debug log: $msg";
}

sub error {
	my ($self, $msg) = @_;
	push @{ $self->{error} }, $msg;
	warn "# error log: $msg";
}

sub access {
	my ($self, $msg) = @_;
	push @{ $self->{access} }, $msg;
	warn "# access log: $msg";
}

sub getLastLogEntry {
	my ($self, $code) = @_;
	return pop @{ $self->{$code} };
}

sub createTestSession {
	my ($self, $args) = @_;
	my $s = Eldhelm::Test::Mock::Session->new(%$args);
	$self->{testSessions}{ $s->id } = $s;
	return $s;
}

sub getPersist {
	my ($self, $id) = @_;
	return if !$id;

	return $self->{testSessions}{$id};
}

1;
