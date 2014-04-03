package Eldhelm::Test::Fixture::MainTester;

use strict;
use Data::Dumper;
use threads;
use threads::shared;

use base qw(Eldhelm::Server::Main);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	return bless $self, $class;
}

sub addSockets {
	my ($self, @list) = @_;
	$self->{sockCnt} ||= 1;
	foreach (@list) {
		$self->{connections}{ $self->{sockCnt} } = shared_clone({});
		$self->{fnoToConidMap}{ $_->fileno } = $self->{sockCnt};
		$self->{sockCnt}++;
	}
}

sub executeTask {
	my ($self, $sock, $data) = @_;

	my $fno = $sock->fileno;
	my $id  = $self->{fnoToConidMap}{$fno};

	if ($data->{proto} eq "System") {
		$self->handleTransmissionFlags($sock, $id, $data);
	}

	push @{ $self->{parsedData} }, $data;
	return;
}

sub getNextParsed {
	my ($self) = @_;
	return shift @{ $self->{parsedData} };
}

sub parsedCount {
	my ($self) = @_;
	return scalar @{ $self->{parsedData} };
}

sub message {
	my ($self, $a) = @_;
	warn $a;
}

sub log {
	my ($self, $a, $tp) = @_;
	warn $tp.": ".$$a;
}

sub error {
	my ($self, $msg) = @_;
	push @{ $self->{parsedErrors} }, $msg;
}

sub clearErrors {
	my ($self) = @_;
	$self->{parsedErrors} = [];
}

sub addToStreamNoRef {
	my ($self, $sock, $str) = @_;
	$self->addToStream($sock, \$str);
}

1;
