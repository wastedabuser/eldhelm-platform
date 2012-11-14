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
	open FR, $path or confess "Can not load '$path': $@";
	my $src = $self->{source} = join "", <FR>;
	close FR;
	return $src;
}

sub compile {
	my ($self, $args) = @_;
	my $source = $self->load;
	my $args = { %{ $self->{params} }, %{ $args || {} } };
	$source =~ s/\$([a-z0-9_]+)/$args->{$1}/gei;
	$source =~ s/\{([a-z0-9_]+?)\|(.+?)\}/$self->interpolateVar($args->{$1}, $2)/gei;
	$source =~ s/\{([a-z0-9_]+?)\}/$args->{$1}/gei;
	$source =~ s/\{([a-z]+)[\t\s\r\n]+(.+?)\}/$self->interpolateFunction($1, $2, $args)/geis;
	return $source;
}

sub interpolateVar {
	my ($self, $value, $format) = @_;
	my $method = "_format_$format";
	return sprintf($value, $format) if $format =~ /%/;
	confess "Format '$format' is unrecognized:\n".Dumper($value) if !$self->can($method);
	return $self->$method($value, $format);
}

sub _format_json {
	my ($self, $value) = @_;
	confess "Please provide an object" unless $value;
	return Eldhelm::Server::Parser::Json->encodeFixNumbers($value);
}

sub interpolateFunction {
	my ($self, $method, $query, $args) = @_;
	my $name = "_function_$method";
	my %params = $query =~ m/([a-z0-9]+):[\s\t]*(.+?)(?:;|$)/gsi;
	return $self->$name(\%params, $args);
}

sub reachNode {
	my ($self, $path, $args) = @_;
	my @path = split /\./, $path;
	my $ref = $args;
	foreach (@path) {
		if (ref $ref eq "HASH") {
			$ref = $ref->{$_};
		} elsif (ref $ref eq "ARRAY") {
			$ref = $ref->[$_];
		} else {
			confess "Path '$path' is not accessible in:\n".Dumper($args);
		}
	}
	return $ref;
}

sub _function_include {
	my ($self, $options, $args) = @_;
	return Eldhelm::Util::Template->new(
		name   => $options->{tpl},
		params => $self->reachNode($options->{ns}, $args),
	)->compile;
}

1;
