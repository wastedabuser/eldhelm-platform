package Perl::Critic::Policy::Eldhelm::AlwaysIncludePackagesWhenUsed;

=pod

=head1 NAME

Perl::Critic::Policy::Eldhelm::AlwaysIncludePackagesWhenUsed

=head1 DESCRIPTION

A perl critic policy which nags when you use a package without explicitly calling use package; in your source.

=head1 METHODS

=over

=cut

use 5.006001;
use strict;
use warnings;

use Readonly;
use Data::Dumper;

use Perl::Critic::Utils qw{ :severities };
use base 'Perl::Critic::Policy';

our $VERSION = '1.0';

#-----------------------------------------------------------------------------

Readonly::Scalar my $DESC => q{package used but never declared - Crticial!};
Readonly::Scalar my $EXPL => [];

#-----------------------------------------------------------------------------

sub supported_parameters { return () }

sub default_severity { return $SEVERITY_MEDIUM }
sub default_themes   { return () }
sub applies_to       { return 'PPI::Document' }

#-----------------------------------------------------------------------------

sub violates {
	my ($self, $elem, undef) = @_;

	my $cont     = $elem->content;
	my %declared = map { +$_ => 1 } $cont =~ /^[\s\t]*(?:use|package|require)[\s\t].*?['"]?([\w:]+)['"]?;/gm;
	my @uses     = grep { $_ !~ /SUPER/ } $cont =~ /(\w+::[\w:]+)/g;

	foreach (@uses) {
		return $self->violation("$_ ".$DESC, $EXPL, $elem) unless $declared{$_};
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
