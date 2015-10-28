package Eldhelm::Util::Template;

=pod

=head1 NAME

Eldhelm::Util::Template - A light template engine.

=head1 SYNOPSIS

	my $t = Eldhelm::Util::Template->new(
		rootPath => 
			'/home/projects/myProject/Eldhelm/Application/Template',
		name => 'pages.page1',
		params => {
			a => 1,
			b => 2
		}
	);
	
	$t->comple({
		c => 3
	});

=head1 DESCRIPTION

Parses template files with the C<.tpl> extension. Contained inside a folder and referenced via names in dotted notation.
Please see C<new> method for more details.

Supports the following features:

=over

=item {var} - variables

Varibales are values directly interpolated into the template.
The C<{var}> will be directly replaced with the value of C<< $self->{params}{var} >>.

=item {var|format} - foratted variables

C<boolean> - formats value as boolean. Writes either C<true> or C<false>.

C<json> - JSON encodes the value.

C<css> - Formats the value as CSS key pairs.

C<html> - HTML encodes some special symbols, converts new lines to <br> and links to <a>

C<htmlTemplateEncoded> - Extends the html format by html encoding the { and } symbols.

C<template> - Formats the values as a predefined template, see the C<template> section bellow.

=item {function arguments} - functions

C<extends> - Inherits another template. You can redefine the C<block> elements to override them with new content.

C<include> - Includes another template.

C<instruct> - Instructs the template engine to generate a template instruction. Useful when you are using templates to generate templates.

=item {block name-or-argument}{block} - blocks and constructs

C<block> - These are named blocks. Their usage is to label a region. Then when other template extends the current one he is able to override these blocks.

C<foreach> - Duplicates the content of the foreach block according to the value.
C<< {foreach var}<div>{join.}</div>{foreach} >> if C<var> is C<< [1,2,3] >> and produces C<< <div>1</div><div>2</div><div>3</div> >>
C<< {foreach var}<div>{join.a}</div>{foreach} >> if C<var> is C<< [{a=>1},{b=>2}] >> and produces C<< <div>1</div><div>2</div> >>

C<join> - Joins the values provided.
C<{join var}{join.}{join}> if C<var> is C<< [1,2,3] >> and produces C<123>
C<{join var}{join.a}{join}> if C<var> is C<< [{a=>1},{b=>2}] >> and produces C<12>

C<separator> Defines a separator to be used for join
C<{separator var},{separator}> Defines a separator as comma.

=item {template name}{template} - Defines a template to be used when a template format is selected

C<< {var|template} >>
C<< {template text}<p>{template.}</p>{template} >>
C<< {template block}<div>{template.a}</div>{template} >>

Let's imagine C<var> is:

	[
		[ 'text', 'My text here' ],
		[ 'block', { a => 'My block here' }]
	]

This will produce the output: C<< <p>My text here</p><div>My block here</div> >>.

=item {cdata-open}{cdata-close} - CDATA. Everything in this block is outputed as is without beeing parsed.

=back

=head1 METHODS

=over

=cut

use strict;
use Data::Dumper;
use Eldhelm::Server::Parser::Json;
use Eldhelm::Util::Factory;
use Carp;

=item new(%args)

Constructs a new object.

C<%args> Hash - Constructor arguments;

C<rootPath> - Template storage location;
C<name> - Template file name in dotted notation;
C<params> HashRef - Compile params;

The C<name> should describe the template location relative to the C<rootPath> supplied.

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {
		rootPath => $args{rootPath},
		name     => $args{name},
		params   => $args{params} || {},
		var      => {},
		function => {},
		cdata    => {}
	};
	bless $self, $class;

	$self->parse if $self->{name};

	return $self;
}

sub getPath {
	my ($self, $name) = @_;
	my $relPath = 'Eldhelm/Application/Template/'.join('/', split(/\./, $name)).'.tpl';
	return $self->{rootPath}.$relPath if $self->{rootPath};
	return Eldhelm::Util::Factory->getAbsoluteClassPath($relPath) || $relPath;
}

=item load($name) self

Loads a template from a file.

C<$name> String - The file path.

=cut

sub load {
	my ($self, $name) = @_;
	my $path = $self->getPath($name || $self->{name});
	open FR, $path or confess "Can not load '$path' with params: ".Dumper($self->{params})."$!";
	my $src = $self->{source} = join "", <FR>;
	close FR;
	return $src;
}

=item parse($stream) self

Parses a teplate from a string.

C<$stream> String - The template to be parsed;

=cut

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
	return $source unless $source =~ /\{[a-z].*?\}/;

	$source =~
		s/\{(block|template|foreach|join|separator)\s+(.+?)\s*\}(.*?)\{\1\}/my($a,$b)=($1,$2); $self->{$a} ||= {}; $self->{$a}{$b}=$self->parseSource($3); ";;~~eldhelm~template~placeholder~$a~$a~$b~~;;"/gsei;

	my $z = -1;
	$source =~
		s/\{cdata-open\}(.*?)\{cdata-close\}/$z++; $self->{cdata}{$z} = $1; ";;~~eldhelm~template~placeholder~cdata~cdata~$z~~;;";/gsei;

	my $vars = $self->{var};
	$source =~ s/\{([a-z][a-z0-9_\.]*)\|(.+?)\}/$vars->{$1} = $2; ";;~~eldhelm~template~placeholder~var~$1~$2~~;;"/gei;
	$source =~ s/\{([a-z][a-z0-9_\.]*)\}/$vars->{$1} = undef; ";;~~eldhelm~template~placeholder~var~$1~none~~;;"/gei;

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

=item compile($args) String

Compiles the template to a stream.

C<$args> HashRef - Optional; Additional compile arguments;

=cut

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
	my ($self, $name, $format) = @_;
	my $value;
	if ($name =~ /\./) {
		my $ref = $self->{compileParams};
		foreach (split /\./, $name) {
			my $rfn = ref $ref;
			confess "The var '$name' can not be traversed. There is a value '$ref' at '$_' instead of HASH or ARRAY!\n"
				unless $rfn;
			unless ($ref->{$_}) {
				$ref = '';
				last;
			}
			if ($rfn eq 'HASH') {
				$ref = $ref->{$_};
			} elsif ($rfn eq 'ARRAY') {
				$ref = $ref->[$_];
			} else {
				confess "The var '$name' can not be traversed. There is a '$rfn' at '$_' instead of HASH or ARRAY!\n";
			}
		}
		confess "The traversed value for the var '$name' is a ".ref($ref)." instead of SCALAR!\n"
			if ref($ref) && $format ne 'template';
		$value = $ref;
	} else {
		$value = $self->{compileParams}{$name};
	}
	return $value if !$format || $format eq 'none';

	my $method = "_format_$format";
	return sprintf($value, $format) if $format =~ /%/;
	confess "Format '$format' is unrecognized:\n".Dumper($value) if !$self->can($method);
	return $self->$method($value, $format, $name);
}

sub _interpolate_function {
	my ($self, $fnm, $name, $query) = @_;
	$name = "_function_$fnm";
	my %params = $query =~ m/([a-z0-9]+):[\s\t]*(.+?)(?:;|$)/gsi;
	return $self->$name(%params ? \%params : $query);
}

sub _interpolate_block {
	my ($self, $fnm, $name, $content) = @_;
	return $self->compileStream($content);
}

sub _interpolate_foreach {
	my ($self, $fnm, $name, $content) = @_;
	my $list = $self->reachNode($name, $self->{compileParams});
	return '' if !$list || ref($list) ne "ARRAY" || !@$list;
	
	my $v = $self->{compileParams};
	return join '', map { $v->{foreach} = $_; $self->compileStream($content) } @$list;
}

sub _interpolate_join {
	my ($self, $fnm, $name, $content) = @_;
	my $list = $self->reachNode($name, $self->{compileParams});
	return '' if !$list || ref($list) ne "ARRAY" || !@$list;
	
	my $v = $self->{compileParams};
	return join $self->{separator}{$name} || ' ', map { $v->{join} = $_; $self->compileStream($content) } @$list;
}

sub _interpolate_template {
	my ($self, $fnm, $name, $content) = @_;
	return '';
}

sub _interpolate_separator {
	my ($self, $fnm, $name, $content) = @_;
	return '';
}

sub _interpolate_cdata {
	my ($self, $fnm, $name, $content) = @_;
	return $content;
}

sub _format_json {
	my ($self, $value, $format, $name) = @_;
	confess "Please provide an object for json formatting of var $name instead of '$value'" unless ref $value;
	return Eldhelm::Server::Parser::Json->encodeFixNumbers($value);
}

sub _format_css {
	my ($self, $value, $format, $name) = @_;
	return $value unless ref $value;
	return join ' ', map { "$_: $value->{$_};" } keys %$value;
}

sub _format_html {
	my ($self, $value, $format, $name) = @_;
	if (!ref $value) {
		$value =~ s/&/&amp;/g;
		$value =~ s/</&lt;/g;
		$value =~ s/>/&gt;/g;
		$value =~ s/"/&quot;/g;
		$value =~ s/\r//sg;
		$value =~ s/\n/<br>\n/sg;
		$value =~ s/\t/&nbsp;&nbsp;&nbsp;&nbsp;/g;
		$value =~ s~(https?://[a-z0-9_%&+:/\-\.\?]+)~<a href="\1">\1</a>~i;
		return $value;
	}
	confess "Can not format $value at $name to html. Encoding to html from a reference is not yet implemented";
}

sub _format_htmlTemplateEncoded {
	my ($self, $value, $format, $name) = @_;
	$value = $self->_format_html($value, $format, $name);
	$value =~ s/\{/&#123;/g;
	$value =~ s/\}/&#125;/g;
	return $value;
}

sub _format_boolean {
	my ($self, $value, $format, $name) = @_;
	return $value ? 'true' : 'false';
}

sub _format_template {
	my ($self, $value, $format, $name) = @_;
	return '' if !$value || ref($value) ne "ARRAY" || !@$value;
	
	my $v = $self->{compileParams};
	return join '', map { $v->{template} = $_->[1]; $self->compileStream($self->{template}{$_->[0]}) } @$value;
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

sub _function_instruct {
	my ($self, $name) = @_;
	return "{$name}";
}

sub reachNode {
	my ($self, $path, $args) = @_;
	my @path = split /\./, $path;
	my $ref = $args;
	foreach (@path) {
		confess "Path '$path' is not accessible via ".ref($ref)." in:\n".Dumper($args) if ref $ref ne 'HASH';
		$ref = $ref->{$_};
	}
	return $ref;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
