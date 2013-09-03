package Eldhelm::Basic::View::BasicPage;

use strict;

use base qw(Eldhelm::Basic::View);

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Basic::View->new(%args);
	$self->{headerTpl}  = $args{headerTpl};
	$self->{contentTpl} = $args{contentTpl};
	$self->{footerTpl}  = $args{footerTpl};
	bless $self, $class;

	$self->{tplArgs}{sessionId} = $self->{data}{sessionId};

	return $self;
}

sub compile {
	my ($self) = @_;
	return join "\n",
		map { $self->applyTemplate($self->{$_}, $self->{tplArgs}) }
		grep { $self->{$_} } qw(headerTpl contentTpl footerTpl);
}

1;
