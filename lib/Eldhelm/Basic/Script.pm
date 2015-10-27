package Eldhelm::Basic::Script;

=pod

=head1 NAME

Eldhelm::Basic::Script - A basic external script loader.

=head1 SYNOPSIS

You should not construct an object directly. You should use:

	Eldhelm::Basic::Controller->getScript

=head1 DESCRIPTION

This class provides a standartization of the naming and location of external scripts.

=head1 METHODS

=over

=cut

use strict;
use Data::Dumper;
use Carp;

=item new(%args)

Constructs a new object.

C<%args> Hash - Contructor argumets;

C<file> String - A path to file;
C<stream> String - A perl script as stream;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {
		
	};
	bless $self, $class;

	$self->init(\%args);

	return $self;
}

sub init {
	my ($self, $args) = @_;
	foreach (qw(file stream)) {
		next unless $args->{$_};
		$self->$_($args->{$_});
	}
}

sub getPath {
	my ($self, $name) = @_;
	return "$self->{rootPath}Eldhelm/Application/Template/".join("/", split(/\./, $name)).".pl";
}

sub find_path {
	my ($self, $path) = @_;
	my $pt = $self->getPath($path);
	confess "Can not find file: $pt" unless $pt;

	$path =~ s|/([^/]+)$||;
	$self->{file_name} = $1;
	$self->{path}      = $path;

	return $pt;
}

sub load_file {
	my ($self, $path) = @_;
	$path = $self->find_path($path);
	open FR, $path or confess "Can not load path: $path; $!";
	$self->{stream} = join "\n", <FR>;
	close FR;
	return;
}

sub load_stream {
	my ($self, $stream) = @_;
	$self->{stream} = $stream;
	return;
}

sub file {
	my ($self, $path) = @_;
	$self->load_file($path);
	return $self;
}

sub stream {
	my ($self, $str) = @_;
	$self->load_stream($str);
	return $self;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
