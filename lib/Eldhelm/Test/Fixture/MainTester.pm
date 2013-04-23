package Eldhelm::Test::Fixture::MainTester;

use strict;
use base qw(Eldhelm::Server::Main);

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Main->new(%args);
	return bless $self, $class;
}

sub executeBufferedTask {
	my ($self, $sock, $buff) = @_;
	$self->message("execute bufered task");
	delete $self->{buffMap}{ $sock->fileno };

	push @{ $self->{parsedData} }, $buff;

	return;
}

sub getNextParsed {
	my ($self) = @_;
	return shift @{ $self->{parsedData} };
}

sub parsedCound {
	my ($self) = @_;
	return scalar @{ $self->{parsedData} };
}

sub error {
	my ($self, $msg) = @_;
	push @{ $self->{parsedErrors} }, $msg;
}

sub clearErrors {
	my ($self) = @_;
	$self->{parsedErrors} = [];
}

1;
