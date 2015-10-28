package Eldhelm::Pod::Parser;

=pod

=head1 NAME

Eldhelm::Pod::Parser - A light parser for PODs.

=head1 SYNOPSIS



=head1 METHODS

=over

=cut

use strict;

use Eldhelm::Util::FileSystem;
use Data::Dumper;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	$self->parseFile($self->{file}) if $self->{file};

	return $self;
}

sub load {
	my ($self, $path) = @_;
	$self->{file} = $path;
	return Eldhelm::Util::FileSystem->getFileContents($path);
}

sub parseFile {
	my ($self, $path) = @_;
	return $self->parse($self->load($path));
}

sub parseInheritance {
	my ($self, $stream) = @_;

	my $data = $self->{data} = {};
	$stream =~ s/(^|[\n\r])=[a-z]+.+?=cut//sg;
	my ($name) = $stream =~ m/^[\s\t]*package (.+);/m;
	$data->{className} = $name;

	my ($extends) = $stream =~ m/^[\s\t]*use (?:base|parent) (.+);/m;
	if ($extends) {
		if ($extends =~ m/qw[\s\t]*[\(\[](.+)[\)\]]/) {
			$data->{extends} = [ split /\s/, $1 ];
		} elsif ($extends =~ m/["'](.+)["']/) {
			$data->{extends} = [$1];
		}

		my $lfn     = $self->libFileName;
		my $lfnw    = $self->libFileNameWin;
		my $libRoot = $self->{file};
		$libRoot =~ s/$lfn//;
		$libRoot =~ s/$lfnw//;
		(my $eFile = $data->{extends}[0]) =~ s|::|/|g;

		my $parser = Eldhelm::Pod::Parser->new;
		eval {
			$parser->parse($parser->load($libRoot.$eFile.'.pm'));
			$data->{inheritance} = [ $parser->inheritance, $name ];
			$data->{inheritedMethods} = [ sort { $a->{name} cmp $b->{name} } $parser->inheritedMethods ];
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
	return unless $self->hasDoc;

	my ($pname, $pindex, $lcName, $mode);
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
				push @{ $data->{$mode} }, { name => $name, description => $self->parseText($text) };
			} else {
				$name = $pn;
				$name =~ s/^\s+//;
				$name =~ s/[.\s\t\n\r]+$//;
				push @{ $data->{$mode} }, { name => $name };
			}

		}

	}

	my $methods = $data->{methodsItems};
	my ($constructor) = grep { $_->{name} =~ /\s*new\s*\(/ } @$methods;
	@$methods = grep { $_->{name} !~ /\s*new\s*\(/ } @$methods;
	@$methods = sort { $a->{name} cmp $b->{name} } @$methods;
	unshift @$methods, $constructor if $constructor;
	push @$methods, @{ $data->{inheritedMethods} } if $data->{inheritedMethods};

	# warn Dumper $data;
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

sub hasDoc {
	my ($self) = @_;
	return $self->{docCount} > 1;
}

sub name {
	my ($self) = @_;
	return $self->{data}{className};
}

sub data {
	my ($self) = @_;
	return $self->{data};
}

sub inheritance {
	my ($self) = @_;
	my $inh = $self->{data}{inheritance};
	return $inh ? @$inh : ();
}

sub inheritedMethods {
	my ($self) = @_;
	my $methods = $self->{data}{methodsItems};
	return $methods ? grep { $_->{name} !~ /\s*new\s*\(/ } @$methods : ();
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
