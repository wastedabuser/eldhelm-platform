package Perl::Critic::Policy::Eldhelm::ProhibitCallingBaseConstructorByClassName;

=pod

=head1 NAME

Perl::Critic::Policy::Eldhelm::ProhibitCallingBaseConstructorByClassName

=head1 DESCRIPTION

A perl critic policy which nags when you call the parent constructor like this MyParentPackage::MyParentName->new() instead of SUPER::new().

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

Readonly::Scalar my $DESC => q{Base constructor called by CLASS->new() instead of SUPER::new() };
Readonly::Scalar my $EXPL => [];

#-----------------------------------------------------------------------------

sub supported_parameters { return () }

sub default_severity { return $SEVERITY_MEDIUM }
sub default_themes   { return () }
sub applies_to       { return 'PPI::Statement::Sub' }

#-----------------------------------------------------------------------------

sub violates {
	my ($self, $elem, undef) = @_;

	return if $elem->name ne 'new';

	my $block = $elem->find('PPI::Structure::Block');
	return if !$block || !@$block;
	
	if ($block->[0] =~ m/my\s+\$self\s+=\s+(.+?)->new/) {
		return $self->violation($DESC, $EXPL, $block->[0]);
	}

	return;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
