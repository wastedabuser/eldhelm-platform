package Eldhelm::Pod::Validator;

=pod

=head1 NAME

Eldhelm::Pod::Validator - A POD validator.

=head1 SYNOPSIS

	my $parser = Eldhelm::Pod::Parser->new(
		# see docs for
		# Eldhelm::Pod::Parser
	);

	my $v = Eldhelm::Pod::Validator->new(
		parser => $parser
	);
	
	# get @issues with the parsed POD
	my @issues = $v->validate;

=head1 DESCRIPTION

This class is used to identify issues within a POD documentation like missing data or wrong syntax.

=head1 METHODS

=over

=cut

use strict;

use Data::Dumper;
use Carp;

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<parser> Eldhelm::Pod::Parser - A parser class containing parsed document;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	return $self;
}

=item validate() Array

Validates the parsed document and returns an array of issues (if any)

=cut

sub validate {
	my ($self) = @_;

	confess 'No parser available!' unless $self->{parser};

	my @issues;
	my $data = $self->{parser}->data;

	foreach (qw(name synopsis description methodsItems author license)) {
		push @issues, "No head1 '$_' POD block defined." unless $data->{$_};
	}

	if ($data->{synopsis}) {
		push @issues, 'The synopsis POD block is useless without a code block with an example.'
			if ref($data->{synopsis}) ne 'ARRAY' || !grep { $_->[0] eq 'code-block' } @{ $data->{synopsis} };
	}

	if ($data->{constructor} && $data->{methodsItems}) {
		push @issues, 'No item POD block for the class constructor.'
			unless grep { $_->{name} =~ /^new[\s\t]*\(/ } @{ $data->{methodsItems} };
	}

	if ($data->{methodsItems}) {
		my %grouped = map { +$_->{name} => 1 } @{ $data->{methodsItems} };
		foreach (@{ $data->{methodsItems} }) {
			if ($grouped{ $_->{name} }) {
				delete $grouped{ $_->{name} };
				next;
			}
			push @issues, "There is a duplicated method item $_->{name} POD block.";
		}
	}

	return @issues;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
