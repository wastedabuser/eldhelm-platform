package Eldhelm::Test::Mock::Router;

use strict;
use Carp;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = { %args };
	bless $self, $class;
	
	return $self;
}

sub route {
	my $self = shift @_;
	confess 'callback not defined' unless $self->{callback};
	$self->{callback}->(@_);
}

sub getInstance {
	my $self = shift @_;
	confess 'instanceCallback not defined' unless $self->{instanceCallback};
	$self->{instanceCallback}->(@_);
}

1;
