package Eldhelm::Perl::SourceParser;

=pod

=head1 NAME

Eldhelm::Perl::SourceParser - A light perl source file parser.

=head1 SYNOPSIS

	my $v = Eldhelm::Perl::SourceParser->new(
		stream => $stream
	);

=head1 DESCRIPTION

This class is used to get a basic understanding what a perl source is. Gets things like class name and a pranet class from a source stream.

=head1 METHODS

=over

=cut

use strict;

use Eldhelm::Util::FileSystem;
use Data::Dumper;
use Carp;

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<stream> String - The source stream;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->{data} = $self->parse($args{stream})   if $args{stream};
	$self->{data} = $self->parseFile($args{file}) if $args{file};

	return $self;
}

=item parseFile($file) HashRef

Parses a perl source from a file and returns a structure of parsed properties

C<$file> String - Perl source file;

=cut

sub parseFile {
	my ($self, $file) = @_;
	return $self->parse(Eldhelm::Util::FileSystem->getFileContents($file));
}

=item parse($stream, $data) HashRef

Parses a perl source and returns a structure of parsed properties

C<$source> String - Perl source stream;
C<$data> HashRef - An object to hold the parsed properties;

=cut

sub parse {
	my ($self, $stream, $data) = @_;

	$data ||= {};

	my ($name) = $stream =~ m/^[\s\t]*package (.+);/m;
	$data->{className} = $name;

	my ($extends) = $stream =~ m/^[\s\t]*use (?:base|parent) (.+);/m;
	if ($extends) {
		if ($extends =~ m/qw[\s\t]*[\(\[](.+)[\)\]]/) {
			$data->{extends} = [ split /\s/, $1 ];
		} elsif ($extends =~ m/["'](.+)["']/) {
			$data->{extends} = [$1];
		}
	}

	my @ts = $stream =~ /###\s*UNIT TEST:\s*(.+?)\s*###/g;
	$data->{unitTests} = \@ts;
	
	return $data;
}

=item data() HashRef

Returns the parsed data structure.

=cut

sub data {
	my ($self) = @_;
	return $self->{data};
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
