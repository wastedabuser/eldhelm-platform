package Perl::Critic::Policy::Eldhelm::ProhibitUsingBaseInsteadOfParent;

=pod

=head1 NAME

Perl::Critic::Policy::Eldhelm::ProhibitUsingBaseInsteadOfParent

=head1 DESCRIPTION

A perl critic policy which nags when you C<use base> instead of C<use parent> without C<use fields>.
Also when you type only one class with qw() instead of just ''.

=head1 METHODS

=over

=cut

use 5.006001;
use strict;
use warnings;

use Readonly;

use Perl::Critic::Utils qw{ :severities };
use base 'Perl::Critic::Policy';

our $VERSION = '1.0';

#-----------------------------------------------------------------------------

Readonly::Scalar my $DESC => q{'use base' used instead of 'use parent' - Crticial!};
Readonly::Scalar my $DESC2 => q{qw() used when there is only one parent class};
Readonly::Scalar my $EXPL => [];

#-----------------------------------------------------------------------------

sub supported_parameters { return () }

sub default_severity { return $SEVERITY_MEDIUM }
sub default_themes   { return () }
sub applies_to       { return 'PPI::Statement::Include' }

#-----------------------------------------------------------------------------

sub violates {
	my ($self, $elem, undef) = @_;

	my $cont = $elem->content;
	if ($cont =~ /use[\s\t]+parent[\s\t]+qw[\s\t]*[\(\[][\s\t]*(.+?)[\s\t]*[\)\]]/) {
		return if scalar(split /[\s\t]+/, $1) > 1;
		return $self->violation($DESC2, $EXPL, $elem);
	}
	return unless $cont =~ /use[\s\t]+base/;
	
	my $doc = $elem->document->content;
	return if $doc =~ /use[\s\t]+fields/;
	
	return $self->violation($DESC, $EXPL, $elem);
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
