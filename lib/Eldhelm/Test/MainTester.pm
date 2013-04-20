package Eldhelm::Test::MainTester;

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
	
	$self->{parsedData} = $buff;
	
	return;
}

1;