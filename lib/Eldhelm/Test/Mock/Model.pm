package Eldhelm::Test::Mock::Model;

use strict;
use Carp;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = { %args };
	bless $self, $class;

	return $self;
}

sub AUTOLOAD {
	my $self = shift;

	my $method = our $AUTOLOAD;
	$method =~ s/^.*:://;
	
	confess "Can not call method '$method' via autoload on not blessed reference" unless ref $self;

	if ($self->can($method)) {
		return $self->$method(@_);
	} elsif (ref $self->{$method} eq "CODE") {
		return $self->{$method}($self, @_);
	} else {
		confess "Can not find method '$method'";
	}
}

sub DESTROY { }

1;