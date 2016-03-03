package Eldhelm::Pod::Parser;

=pod

=head1 NAME

Eldhelm::Pod::Parser - A light parser for PODs.

=head1 SYNOPSIS

	my $p = Eldhelm::Pod::Parser->new(
		file => '<path to a pm.file>'
	);
	
	# get $parsed data
	$p->data;

=head1 DESCRIPTION

This parser is designed to produce output compatible with L<Eldhelm::Util::Template>. 
Also it resolves class naming and inheritance based on the perl source code - not necessary for a class to have pods at all.

It is only a light parser and does not support many pod notations and nested constructs.

Currently supports the following blocks:
head1
over
item
back

And the following formats:
B<bold>
I<italic>
U<underline>
C<code>
L<Eldhelm::Pod::Parser> - links

It sucesfully understands indented paragraphs as: 

	'source code'

=head1 METHODS

=over

=cut

use strict;

use Eldhelm::Util::FileSystem;
use Eldhelm::Util::StringUtil;
use Eldhelm::Perl::SourceParser;
use Data::Dumper;
use Carp;

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<file> String - Path to file;
C<libPath> String - Path to the base classes;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->{sourceParser} = Eldhelm::Perl::SourceParser->new;
	$self->parseFile($self->{file}) if $self->{file};

	return $self;
}

sub load {
	my ($self, $path) = @_;
	$self->{file} = $path;
	return Eldhelm::Util::FileSystem->getFileContents($path);
}

=item parseFile($path) HashRef

Parses a file and returns the parsed data.

C<$path> String - The file to be parsed.

=cut

sub parseFile {
	my ($self, $path) = @_;
	return $self->parse($self->load($path));
}

sub parseInheritance {
	my ($self, $stream) = @_;

	my $data = $self->{data} = {};
	$stream =~ s/(^|[\n\r])=[a-z]+.+?=cut//sg;

	$self->{sourceParser}->parse($stream, $data);
	my $name = $data->{className};

	if ($data->{extends}) {
		my $lfn     = $self->libFileName;
		my $lfnw    = $self->libFileNameWin;
		my $libRoot = $self->{file};
		$libRoot =~ s/$lfn//;
		$libRoot =~ s/$lfnw//;
		(my $eFile = $data->{extends}[0]) =~ s|::|/|g;
		my $appPath = $libRoot.$eFile.'.pm';
		unless (-f $appPath) {
			$appPath = $self->{libPath}.'/'.$eFile.'.pm';
		}

		my $parser = $self->{parent} = Eldhelm::Pod::Parser->new(libPath => $self->{libPath});
		eval {
			$parser->parseFile($appPath);
			$data->{inheritance} = [ $parser->inheritance, $name ];
		} or do {
			warn $@;
			$data->{inheritance} = [ $data->{extends}[0], $name ];
		};

	} else {
		$data->{inheritance} = [$name];
	}
	return $data;
}

sub parse {
	my ($self, $stream) = @_;

	my $data = $self->parseInheritance($stream);

	my @chunks = split /[\n\r]+(\=[a-z0-9]+)/, $stream;
	$self->{docCount} = scalar @chunks;
	if ($self->hasDoc) {
		my ($pname, $pindex, $lcName, $mode) = ('');
		foreach my $pn (@chunks) {
			next unless $pn;

			if ($pn =~ /^=([a-z]+)(\d?)/) {
				$pname  = $1;
				$pindex = $2;

				if ($pname eq 'over') {
					$mode = $lcName.'Items';
					$data->{$mode} ||= [];
				} elsif ($pname eq 'back') {
					$mode = '';
				}

				next;
			}

			if ($pname eq 'head') {
				my ($name, $text) = $pn =~ m/^\s+(.+?)[\n\r]+(.+)/s;
				if ($name) {
					$name            = $1;
					$lcName          = lc($name);
					$data->{$lcName} = $self->parseText($text);
				} else {
					$name = $pn;
					$name =~ s/^\s+//;
					$name =~ s/[.\s\t\n\r]+$//;
					$lcName = lc($name);
				}

			} elsif ($pname eq 'item') {
				my ($name, $text) = $pn =~ m/^\s+(.+?)[\n\r]+(.+)/s;
				next unless $mode;

				if ($name) {
					my ($id) = $name =~ /^(\w+)/;
					$id = Eldhelm::Util::StringUtil->keyCodeFromString($name) unless $id;
					push @{ $data->{$mode} }, { id => $id, name => $name, description => $self->parseText($text) };
				} else {
					$name = $pn;
					$name =~ s/^\s+//;
					$name =~ s/[.\s\t\n\r]+$//;
					push @{ $data->{$mode} }, { name => $name };
				}

			}

		}

		my $methods = $data->{methodsItems};
		($data->{constructor}) = grep { $_->{name} =~ /\s*new\s*\(/ } @$methods;
		@$methods = grep { $_->{name} !~ /\s*new\s*\(/ } @$methods;
		@$methods = sort { $a->{name} cmp $b->{name} } @$methods;
	}

	my $parser = $self->{parent};
	if ($parser) {
		my @inhMethods = $parser->inheritedMethods;
		if (@inhMethods) {
			$data->{methodsItems} ||= [];
			push @{ $data->{methodsItems} },
				{
				id    => 'inherited-methods',
				name  => 'Inherited methods',
				class => 'separator'
				},
				@inhMethods;
		}

		$data->{synopsis}    ||= $parser->synopsis;
		$data->{description} ||= $parser->description;
		if ($data->{constructor}) {
			my @cChunks = $parser->inheritedConstructor;
			unshift @{ $data->{constructor}{description} }, @cChunks, [ 'text', "\n\n" ] if @cChunks;
		} else {
			$data->{constructor} = $parser->constructor;
		}
	}

	if ($data->{constructor}) {
		$data->{methodsItems} ||= [];
		unshift @{ $data->{methodsItems} }, $data->{constructor};
	}
}

sub parseText {
	my ($self, $text) = @_;

	$text =~ s/\r//g;
	my @chunks;
	foreach (split /(\n)/, $text) {
		push @chunks, grep { $_ } split /([BIUCL]<{2,}\s.+?\s>{2,}|[BIUCL]<.+?>)/;
	}

	my @parts;
	my $mode    = 'text';
	my $newMode = 'text';
	my $partStr = '';
	foreach my $l (@chunks) {
		my $str;
		if ($l =~ /^\t(.*)/s) {
			$str     = $1;
			$newMode = 'code-block';
		} elsif ($l =~ /^([BIUCL])(?:\<{2,}\s(.*?)\s>{2,}|<(.*?)>)$/s) {
			$str = $2 || $3;
			$newMode = 'code'      if $1 eq 'C';
			$newMode = 'bold'      if $1 eq 'B';
			$newMode = 'italic'    if $1 eq 'I';
			$newMode = 'underline' if $1 eq 'U';
			$newMode = 'link'      if $1 eq 'L';
		} elsif ($l eq "\n" && ($mode eq 'code-block' || $mode eq 'text')) {
			$str = $l;
		} else {
			$str     = $l;
			$newMode = 'text';
		}
		if ($mode ne $newMode) {
			$partStr =~ s/[\n\t]+$// if $newMode eq 'code-block';
			push @parts, [ $mode, $partStr ];
			$partStr = '';
			$partStr .= $str;
			$partStr =~ s/^[\n\t\s]+// if $mode eq 'code-block';
			$mode = $newMode;
		} else {
			$partStr .= $str;
		}
	}
	push @parts, [ $newMode, $partStr ];

	return \@parts;
}

=item hasDoc() 1 or undef

Checks whether last parse encountered any pods.

=cut

sub hasDoc {
	my ($self) = @_;
	return $self->{docCount} > 1;
}

=item name() String

Returns the class name.

=cut

sub name {
	my ($self) = @_;
	return $self->{data}{className};
}

=item synopsis() ArrayRef

Returns the class synopsis.

=cut

sub synopsis {
	my ($self) = @_;
	return $self->{data}{synopsis};
}

=item description() ArrayRef

Returns the class description.

=cut

sub description {
	my ($self) = @_;
	return $self->{data}{description};
}

=item constructor() ArrayRef

Returns the class constructor.

=cut

sub constructor {
	my ($self) = @_;
	return $self->{data}{constructor};
}

=item data() HashRef

Returns the parsed structure.

=cut

sub data {
	my ($self) = @_;
	return $self->{data};
}

=item inheritance() Array

Returns the inheritance chain of the currently parsed class.

=cut

sub inheritance {
	my ($self) = @_;
	my $inh = $self->{data}{inheritance};
	return $inh ? @$inh : ();
}

=item inheritedConstructor() Array

Returns the inherited constructor of the currently parsed class.

=cut

sub inheritedConstructor {
	my ($self) = @_;
	my $c = $self->{data}{constructor};
	return () unless $c;
	return () unless $c->{description};
	return @{ $c->{description} };
}

=item inheritedMethods() Array

Returns the inherited methods of the currently parsed class.

=cut

sub inheritedMethods {
	my ($self) = @_;
	my $methods = $self->{data}{methodsItems};
	return () unless $methods;
	my @list = sort { $a->{name} cmp $b->{name} } grep { $_->{name} !~ /\s*new\s*\(|Inherited\smethods/ } @$methods;
	return @list;
}

sub libFileName {
	my ($self) = @_;
	my $p = $self->name;
	$p =~ s|::|/|g;
	return $p.'.pm';
}

sub libFileNameWin {
	my ($self) = @_;
	my $p = $self->name;
	$p =~ s|::|\\\\|g;
	return $p.'.pm';
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
