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
	return join("\n",
		$self->applyTemplate($self->{headerTpl},  $self->{tplArgs}),
		$self->applyTemplate($self->{contentTpl}, $self->{tplArgs}),
		$self->applyTemplate($self->{footerTpl},  $self->{tplArgs}),
	);
}

1;
