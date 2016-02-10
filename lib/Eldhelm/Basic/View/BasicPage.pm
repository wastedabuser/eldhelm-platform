package Eldhelm::Basic::View::BasicPage;

=pod

=head1 NAME

Eldhelm::Basic::View::BasicPage - A view with header, content and footer.

=head1 SYNOPSIS

You should not construct this object directly. You should instead use:

	Eldhelm::Basic::Controller->getView(
		'basicPage',
		{
			# args
		}
	);

=head1 METHODS

=over

=cut

use strict;

use Data::Dumper;

use parent 'Eldhelm::Basic::View';

=item new(%args)

C<Eldhelm::Basic::View::BasicPage> provides additional constructor arguments:
C<headerTpl> String - dotted notation of a template template file in the Eldhelm::Application::Template namespace;
C<headerTplArgs> HashRef - compile arguments;
C<contentTpl> String - dotted notation of a template template file in the Eldhelm::Application::Template namespace;
C<contentTplArgs> HashRef - compile arguments;
C<footerTpl> String - dotted notation of a template template file in the Eldhelm::Application::Template namespace;
C<footerTplArgs> HashRef - compile arguments;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->{tpls}    ||= {};
	$self->{tplArgs} ||= {};

	$self->addTemplate($args{headerTpl},  $args{headerTplArgs},  'header')  if $args{headerTpl};
	$self->addTemplate($args{contentTpl}, $args{contentTplArgs}, 'content') if $args{contentTpl};
	$self->addTemplate($args{footerTpl},  $args{footerTplArgs},  'footer')  if $args{footerTpl};

	$self->{tplArgs}{sessionId} = $self->{data}{sessionId};

	return $self;
}

=item addContent($content, $ns)

Appends additional content to the specified namespace.

C<$content> String - Stream of data;
C<$ns> String - Optional; The namespace to append the template to; Could be header, footer, content; Defaults to content;


=cut

sub addContent {
	my ($self, $content, $ns) = @_;
	$ns ||= 'content';
	my $tpls = $self->{tpls};
	$tpls->{$ns} ||= [];
	push @{ $tpls->{$ns} }, [ undef, $content ];
}

=item addTemplate($tpl, $args, $ns)

Appends additional template to the specified namespace.

C<$tpl> String - dotted notation of a template template file in the Eldhelm::Application::Template namespace;
C<$args> HashRef - compile arguments;
C<$ns> String - Optional; The namespace to append the template to; Could be header, footer, content; Defaults to content;

=cut

sub addTemplate {
	my ($self, $tpl, $args, $ns) = @_;
	$args ||= {};
	$ns   ||= 'content';
	my $tpls = $self->{tpls};
	$tpls->{$ns} ||= [];
	push @{ $tpls->{$ns} }, [ $tpl, $args ];
}

=item addTemplateArgs($tpl, $args, $ns)

Adds more arguments to a template in a specified namespace.

C<$tpl> String - dotted notation of a template template file in the Eldhelm::Application::Template namespace;
C<$args> HashRef - compile arguments;
C<$ns> String - Optional; The namespace to append the template to; Could be header, footer, content; Defaults to content;

=cut

sub addTemplateArgs {
	my ($self, $tpl, $args, $ns) = @_;
	return unless $args;

	$ns ||= 'content';
	my $tpls = $self->{tpls};
	my $list = $tpls->{$ns};
	return unless $list;

	foreach my $t (@$list) {
		next if $t->[0] ne $tpl;
		$t->[1] = { %{ $t->[1] }, %$args };
	}
}

sub compile {
	my ($self) = @_;
	my $tpls = $self->{tpls};
	return join "\n", map { $_->[0] ? $self->applyTemplate($_->[0], { %{ $self->{tplArgs} }, %{ $_->[1] } }) : $_->[1] }
		map { @{ $tpls->{$_} } } grep { $tpls->{$_} } qw(header content footer);
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
