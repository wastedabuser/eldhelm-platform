package Eldhelm::Basic::View::BasicPage;

use strict;

use base qw(Eldhelm::Basic::View);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->addTemplate($args{headerTpl},  $args{headerTplArgs},  "header")  if $args{headerTpl};
	$self->addTemplate($args{contentTpl}, $args{contentTplArgs}, "content") if $args{contentTpl};
	$self->addTemplate($args{footerTpl},  $args{footerTplArgs},  "footer")  if $args{footerTpl};

	$self->{tpls}    ||= {};
	$self->{tplArgs} ||= {};
	$self->{tplArgs}{sessionId} = $self->{data}{sessionId};

	return $self;
}

sub addContent {
	my ($self, $content, $ns) = @_;
	$ns ||= "content";
	$self->{tpls}{$ns} ||= [];
	push @{ $self->{tpls}{$ns} }, [ undef, $content ];
}

sub addTemplate {
	my ($self, $tpl, $args, $ns) = @_;
	$args              ||= {};
	$ns                ||= "content";
	$self->{tpls}{$ns} ||= [];
	push @{ $self->{tpls}{$ns} }, [ $tpl, $args ];
}

sub compile {
	my ($self) = @_;
	return join "\n", map { $_->[0] ? $self->applyTemplate($_->[0], { %{ $self->{tplArgs} }, %{ $_->[1] } }) : $_->[1] }
		map { @{ $self->{tpls}{$_} } } grep { $self->{tpls}{$_} } qw(header content footer);
}

1;
