package Eldhelm::Basic::Script;

use strict;
use Data::Dumper;
use Carp;

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

1;
