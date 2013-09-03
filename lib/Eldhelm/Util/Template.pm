package Eldhelm::Util::Template;

use strict;
use Data::Dumper;
use Eldhelm::Server::Parser::Json;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {
		rootPath => $args{rootPath},
		name     => $args{name},
		params   => $args{params} || {},
	};
	bless $self, $class;

	return $self;
}

sub getPath {
	my ($self, $name) = @_;
	return "$self->{rootPath}Eldhelm/Application/Template/".join("/", split(/\./, $name)).".tpl";
}

sub load {
	my ($self, $name) = @_;
	my $path = $self->getPath($name || $self->{name});
	open FR, $path or confess "Can not load '$path' with params: ".Dumper($self->{params})."$!";
	my $src = $self->{source} = join "", <FR>;
	close FR;
	return $src;
}

sub compile {
	my ($self, $args) = @_;
	my $source = $self->load;
	$self->{compileParams} = { %{ $self->{params} }, %{ $args || {} } };

	$source =~ s/\$([a-z][a-z0-9_]*)/;;~~eldhelm~template~placeholder~var~$1~~;;/gi;
	$source =~ s/\{([a-z][a-z0-9_\.]*)\|(.+?)\}/;;~~eldhelm~template~placeholder~var~$1,,$2~~;;/gi;
	$source =~ s/\{([a-z][a-z0-9_\.]*)\}/;;~~eldhelm~template~placeholder~var~$1~~;;/gi;
	$source =~ s/\{([a-z][a-z0-9_]*)[\t\s\r\n]+(.+?)\}/ 
		my $nm = $1; 
		(my $args = $2) =~ s|[\n\r\t]||g;
		";;~~eldhelm~template~placeholder~function~$nm,,$args~~;;"
	/geis;

	$source =~ s/;;~~eldhelm~template~placeholder~(.+?)~(.+?)~~;;/$self->interpolate($1, $2)/gei;

	return $source;
}

sub interpolate {
	my ($self, $tp, $args) = @_;
	my $fn = "_interpolate_$tp";
	return $self->$fn(split /,,/, $args);
}

sub _interpolate_var {
	my ($self, $name, $format) = @_;
	my $value;
	if ($name =~ /\./) {
		my $ref = $self->{compileParams};
		foreach (split /\./, $name) {
			confess "The var '$name' can not be traversed. There is a value '$ref' at '$_' instead of HASH\n"
				unless ref $ref;
			unless ($ref->{$_}) {
				$ref = "";
				last;
			}
			$ref = $ref->{$_};
		}
		confess "The traversed value for the template var '$name' is a ".ref($ref)."\n" if ref $ref;
		$value = $ref;
	} else {
		$value = $self->{compileParams}{$name};
	}
	return $value unless $format;

	my $method = "_format_$format";
	return sprintf($value, $format) if $format =~ /%/;
	confess "Format '$format' is unrecognized:\n".Dumper($value) if !$self->can($method);
	return $self->$method($value, $format);
}

sub _interpolate_function {
	my ($self, $method, $query) = @_;
	my $name = "_function_$method";
	my %params = $query =~ m/([a-z0-9]+):[\s\t]*(.+?)(?:;|$)/gsi;
	return $self->$name(\%params);
}

sub _format_json {
	my ($self, $value) = @_;
	confess "Please provide an object for json formatting" unless $value;
	return Eldhelm::Server::Parser::Json->encodeFixNumbers($value);
}

sub _function_include {
	my ($self, $options) = @_;
	return Eldhelm::Util::Template->new(
		name   => $options->{tpl},
		params => $self->reachNode($options->{ns}, $self->{compileParams}),
	)->compile;
}

sub reachNode {
	my ($self, $path, $args) = @_;
	my @path = split /\./, $path;
	my $ref = $args;
	foreach (@path) {
		confess "Path '$path' is not accessible via ".ref($ref)." in:\n".Dumper($args) if ref $ref ne "HASH";
		$ref = $ref->{$_};
	}
	return $ref;
}

1;
