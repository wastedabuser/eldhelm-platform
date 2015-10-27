package Eldhelm::Pod::DocCompiler;

use strict;

use Eldhelm::Util::FileSystem;
use Eldhelm::Pod::Parser;
use Eldhelm::Util::Template;
use Data::Dumper;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {
		fileNameExtension => 'tpl',
		%args
	};
	bless $self, $class;

	$self->parse($self->{files})                      if $self->{files};
	$self->compile($self->{tpl})                      if $self->{tpl};
	$self->compileContents($self->{contentsTpl})      if $self->{contentsTpl};
	$self->writeOutput($self->{outputFolder})         if $self->{outputFolder};
	$self->writeContents($self->{contentsOutputFile}) if $self->{contentsOutputFile};

	return $self;
}

sub parse {
	my ($self, $paths) = @_;
	my @files;
	foreach my $p (@$paths) {
		if (-f $p) {
			push @files, $p;
		} elsif (-d $p) {
			push @files, Eldhelm::Util::FileSystem->readFileList($p);
		}
	}
	@files = sort { $a cmp $b } @files;

	my @parsed;
	foreach my $f (@files) {
		warn "Parsing $f;" if $self->{debug};
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

	foreach (@{ $self->{compiled} }) {
		my ($p, $c) = @$_;
		my $path = $output.'/'.$self->outputName($p->name);
		warn "Writing $path;" if $self->{debug};

		Eldhelm::Util::FileSystem->writeFileContents($path, $c);
	}
}

sub outputName {
	my ($self, $name) = @_;
	if ($self->{fileNameFormat} eq 'dashes') {
		$name =~ s/::/-/g;
		return lc($name).'.'.$self->{fileNameExtension};
	}
	return $name.'.'.$self->{fileNameExtension};
}

sub compileContents {
	my ($self, $tpl) = @_;

	$self->{contents} = Eldhelm::Util::Template->new(
		name     => $tpl,
		params   => { classes => [ map { { name => $_->[0]->name } } @{ $self->{compiled} } ], },
		rootPath => $self->{rootPath}
	)->compile;

}

sub writeContents {
	my ($self, $output) = @_;
	my $path = "$self->{outputFolder}/$output";
	warn "Writing $path;" if $self->{debug};

	Eldhelm::Util::FileSystem->writeFileContents($path, $self->{contents});
}

1;
