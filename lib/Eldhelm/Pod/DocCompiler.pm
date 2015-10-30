package Eldhelm::Pod::DocCompiler;

=pod

=head1 NAME

Eldhelm::Pod::DocCompiler - A utility for compiling a documentation library.

=head1 SYNOPSIS

	Eldhelm::Pod::DocCompiler->new(
		files => [
			'< path to a pm file >'
		],
		tpl => 'templates.myDocTemplate',
		contentsTpl => 'templates.myContentsTemplate',
		outputFolder => '< where to put the files generated >'
		contentsOutputFile => 'contents',
		fileNameFormat => 'dashed',
		fileNameExtension => 'html'
	);

=head1 METHODS

=over

=cut

use strict;

use Eldhelm::Util::FileSystem;
use Eldhelm::Pod::Parser;
use Eldhelm::Util::Template;
use Data::Dumper;
use Carp;

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<files> ArrayRef - Files to be processed;
C<tpl> String - The teplate of the documentation page.
C<rootPath> String - The path where templates are located;
C<contentsTpl> String - The template of the contents page.
C<outputFolder> String - The folder to write the documentation files;
C<contentsOutputFile> String - The name of the outputed contents file;
C<fileNameFormat> String - File naming format currently cuports only C<dashed> keyword;
C<fileNameExtension> String- The extension of the outputed files;
C<skipFilesWithExtension> String - The extension of the files to skipped; Defaults to C<bak|tmp>;
C<debug> 1 or 0 or undef - Whether to print debug info;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {
		fileNameExtension => 'tpl',
		%args
	};
	bless $self, $class;

	$self->{skipFilesWithExtension} ||= 'bak|tmp';

	$self->parse($self->{files})                      if $self->{files};
	$self->compile($self->{tpl})                      if $self->{tpl};
	$self->compileContents($self->{contentsTpl})      if $self->{contentsTpl};
	$self->writeOutput($self->{outputFolder})         if $self->{outputFolder};
	$self->writeContents($self->{contentsOutputFile}) if $self->{contentsOutputFile};

	return $self;
}

sub parse {
	my ($self, $paths) = @_;
	$self->debug("Parsing...") if $self->{debug};
	my @files;
	foreach my $p (@$paths) {
		if (-f $p) {
			push @files, $p;
		} elsif (-d $p) {
			push @files, Eldhelm::Util::FileSystem->readFileList($p);
		}
	}
	@files = sort { $a cmp $b } @files;

	my $ex = $self->{skipFilesWithExtension};
	$self->debug("Will skip $ex") if $ex && $self->{debug};
	my @parsed;
	foreach my $f (@files) {
		if ($f =~ /(?:$ex)$/) {
			$self->debug(" > Skip $f") if $self->{debug};
			next;
		}
		$self->debug(" > Parsing $f") if $self->{debug};
		push @parsed,
			Eldhelm::Pod::Parser->new(
			debug => $self->{debug},
			file  => $f
			);
	}
	return $self->{parsed} = \@parsed;
}

sub compile {
	my ($self, $tpl) = @_;
	$self->debug("Compiling...") if $self->{debug};
	
	my @compiled;
	foreach my $p (@{ $self->{parsed} }) {
		next unless $p->hasDoc;
		push @compiled, [ $p, $self->compileParsed($tpl, $p) ];
	}
	return $self->{compiled} = \@compiled;
}

sub compileParsed {
	my ($self, $tpl, $parsed) = @_;
	return Eldhelm::Util::Template->new(
		name     => $tpl,
		params   => $parsed->data,
		rootPath => $self->{rootPath}
	)->compile;
}

sub writeOutput {
	my ($self, $output) = @_;
	$self->debug("Writing...") if $self->{debug};
	
	foreach (@{ $self->{compiled} }) {
		my ($p, $c) = @$_;
		my $path = $output.'/'.$self->outputName($p->name);
		my $oldC = Eldhelm::Util::FileSystem->getFileContents($path);
		if ($c eq $oldC) {
			$self->debug(" > Skip $path") if $self->{debug};
			next;
		}
		$self->debug(" > Writing $path") if $self->{debug};
		Eldhelm::Util::FileSystem->writeFileContents($path, $c);
	}
}

sub outputName {
	my ($self, $name) = @_;
	if ($self->{fileNameFormat} eq 'dashes') {
		return join('-', map { lcfirst($_) } split /::/, $name).'.'.$self->{fileNameExtension};
	}
	return $name.'.'.$self->{fileNameExtension};
}

sub compileContents {
	my ($self, $tpl) = @_;
	$self->debug("Compiling contents...") if $self->{debug};
	
	$self->{contents} = Eldhelm::Util::Template->new(
		name     => $tpl,
		params   => { classes => [ map { { name => $_->[0]->name } } @{ $self->{compiled} } ], },
		rootPath => $self->{rootPath}
	)->compile;

}

sub writeContents {
	my ($self, $output) = @_;
	$self->debug("Writing contents...") if $self->{debug};
	my $path = "$self->{outputFolder}/$output";
	my $oldC = Eldhelm::Util::FileSystem->getFileContents($path);
	if ($oldC eq $self->{contents}) {
		$self->debug(" > Skip $path") if $self->{debug};
		return;
	}
	$self->debug(" > Writing $path") if $self->{debug};
	Eldhelm::Util::FileSystem->writeFileContents($path, $self->{contents});
}

sub debug {
	my ($self, $msg) = @_;
	print "$msg\n";
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
