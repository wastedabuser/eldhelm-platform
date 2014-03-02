package Eldhelm::Util::Template;

use strict;
use Data::Dumper;
use Eldhelm::Server::Parser::Json;
use Eldhelm::Util::Factory;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {
		rootPath => $args{rootPath},
		name     => $args{name},
		params   => $args{params} || {},
		var      => {},
		function => {},
		block    => {},
	};
	bless $self, $class;

	$self->parse if $self->{name};

	return $self;
}

sub getPath {
	my ($self, $name) = @_;
	my $relPath = "Eldhelm/Application/Template/".join("/", split(/\./, $name)).".tpl";
	return $self->{rootPath}.$relPath if $self->{rootPath};
	return Eldhelm::Util::Factory->getAbsoluteClassPath($relPath) || $relPath;
}

sub load {
	my ($self, $name) = @_;
	my $path = $self->getPath($name || $self->{name});
	open FR, $path or confess "Can not load '$path' with params: ".Dumper($self->{params})."$!";
	my $src = $self->{source} = join "", <FR>;
	close FR;
	return $src;
}

sub parse {
	my ($self, $stream) = @_;

	$self->{source} = $self->parseSource($stream || $self->load);

	my $fns = $self->{function};
	$self->extend($fns->{extends}) if $fns->{extends};

	return $self;
}

sub parseSource {
	my ($self, $source) = @_;
	return unless $source;

	my $blocks = $self->{block};
	$source =~
		s/\{block\s+(.+?)\s*\}(.*?)\{block\}/$blocks->{$1} = $self->parseSource($2); ";;~~eldhelm~template~placeholder~block~block~$1~~;;"/gei;

	my $vars = $self->{var};
	$source =~ s/\{([a-z][a-z0-9_\.]*)\|(.+?)\}/$vars->{$1} = $2; ";;~~eldhelm~template~placeholder~var~var~$1~~;;"/gei;
	$source =~ s/\{([a-z][a-z0-9_\.]*)\}/$vars->{$1} = undef; ";;~~eldhelm~template~placeholder~var~var~$1~~;;"/gei;

	my $fns = $self->{function};
	my $i   = "";
	$source =~ s/\{([a-z][a-z0-9_]*)(:?[a-z0-9_]*)[\t\s\r\n]+(.+?)\}/ 
		my $fn = $1; 
		my $nm = $2 || "$fn$i";
		$i++;
		(my $args = $3) =~ s|[\n\r\t]||g;
		$fns->{$nm} = $args;
		";;~~eldhelm~template~placeholder~function~$fn~$nm~~;;"
	/geis;

	return $source;
}

sub extend {
	my ($self, $name) = @_;

	my $tpl = Eldhelm::Util::Template->new(
		rootPath => $self->{rootPath},
		name     => $name
	);

	$self->{$_} = { %{ $tpl->{$_} }, %{ $self->{$_} } } foreach qw(block var function);

	$self->{source} = $tpl->{source};

	return $self;
}

sub compile {
	my ($self, $args) = @_;
	$self->{compileParams} = { %{ $self->{params} }, %{ $args || {} } };
	return $self->compileStream($self->{source});
}

sub compileStream {
	my ($self, $source) = @_;
	$source =~ s/;;~~eldhelm~template~placeholder~(.+?)~(.+?)~(.+?)~~;;/$self->interpolate($1, $2, $3)/gei;
	return $source;
}

sub interpolate {
	my ($self, $tp, $fnm, $nm) = @_;
	my $fn = "_interpolate_$tp";
	return $self->$fn($fnm, $nm, $self->{$tp}{$nm});
}

sub _interpolate_var {
	my ($self, $fnm, $name, $format) = @_;
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
	return $self->$method($value, $format, $name);
}

sub _interpolate_function {
	my ($self, $fnm, $name, $query) = @_;
	my $name = "_function_$fnm";
	my %params = $query =~ m/([a-z0-9]+):[\s\t]*(.+?)(?:;|$)/gsi;
	return $self->$name(%params ? \%params : $query);
}

sub _interpolate_block {
	my ($self, $fnm, $name, $content) = @_;
	return $self->compileStream($content);
}

sub _format_json {
	my ($self, $value, $format, $name) = @_;
	confess "Please provide an object for json formatting of var $name instead of '$value'" unless ref $value;
	return Eldhelm::Server::Parser::Json->encodeFixNumbers($value);
}

sub _format_html {
	my ($self, $value, $format, $name) = @_;
	if (!ref $value) {
		$value =~ s/&/&amp;/sg;
		$value =~ s/</&lt;/sg;
		$value =~ s/>/&gt;/sg;
		$value =~ s/"/&quot;/sg;
		return $value;
	}
	confess "Can not format $value at $name to html. Encoding to html from a reference is not yet implemented";
}

sub _format_boolean {
	my ($self, $value, $format, $name) = @_;
	return $value ? "true" : "false";
}

sub _function_include {
	my ($self, $options) = @_;
	my $tpl;
	if (ref $options) {
		$tpl = $options->{tpl};
	} else {
		$tpl     = $options;
		$options = {};
	}
	return Eldhelm::Util::Template->new(
		name   => $tpl,
		params => $self->reachNode($options->{ns}, $self->{compileParams}),
	)->compile;
}

sub _function_extends {
	my ($self, $name) = @_;
	return "";
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
