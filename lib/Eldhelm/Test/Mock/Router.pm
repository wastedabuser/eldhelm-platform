package Eldhelm::Test::Mock::Router;

use strict;
use Carp;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = { %args };
	bless $self, $class;

	confess "callback not defined" unless $self->{callback};
	
	return $self;
}

sub route {
	my $self = shift @_;
	$self->{callback}->(@_);
}

1;
