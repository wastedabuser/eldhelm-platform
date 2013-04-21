package Eldhelm::Test::SessionDummy;

use strict;
use Data::Dumper;
use threads;
use threads::shared;

use base qw(Eldhelm::Basic::Persist);

my @conProps = qw(fno eventFno);

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Basic::Persist->new(
		persistType => __PACKAGE__,
		%args,
		sayData => [],
	);
	bless $self, $class;

	return $self;
}

sub say {
	my ($self, $data) = @_;
	push @{ $self->{sayData} }, shared_clone($data);
}

sub nextSayData {
	my ($self) = @_;
	return shift @{ $self->{sayData} };
}

sub clearSayData {
	my ($self) = @_;
	@{ $self->{sayData} } = ();
}

1;
