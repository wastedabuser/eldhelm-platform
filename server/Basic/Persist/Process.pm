package Eldhelm::Basic::Persist::Process;

use strict;
use Eldhelm::Util::Factory;
use Data::Dumper;

use base qw(Eldhelm::Basic::Persist);

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Basic::Persist->new(%args);
	bless $self, $class;

	$self->{session} = $args{session};

	return $self;
}

sub sessionContext {
	my ($self) = @_;
	$self->worker->{sessionContext};
}

1;
