package Eldhelm::Pod::Parser;

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
	return Eldhelm::Util::FileSystem->getFileContents($path);
}

sub parseFile {
	my ($self, $path) = @_;
	return $self->parse($self->load($path));
}

sub parse {
	my ($self, $stream) = @_;

	my @chunks = split /[\n\r]+(\=[a-z0-9]+)/, $stream;
	return if @chunks < 2;

	my $data = {};
	my ($pname, $pindex, $name, $lcName, $mode);
	foreach my $pn (@chunks) {
		next unless $pn;

		if ($pn =~ /^=([a-z]+)(\d?)/) {
			$pname  = $1;
			$pindex = $2;

			if ($pname eq 'over') {
				$mode = $lcName.'Items';
			} elsif ($pname eq 'back') {
				$mode = '';
			}

			next;
		}

		if ($pname eq 'head') {
			my ($name, $text) = $pn =~ m/^\s+(.+?)[\n\r]+(.+)/s;
			if ($name) {
				$name   = $1;
				$lcName = lc($name);
				$data->{$lcName} .= $text;
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
				push @{ $data->{$mode} }, { name => $name, description => $text };
			} else {
				$name = $pn;
				$name =~ s/^\s+//;
				$name =~ s/[.\s\t\n\r]+$//;
				push @{ $data->{$mode} }, { name => $name };
			}

		}

	}

	$self->{data} = $data;
	($self->{data}{className}) = $self->{data}{name} =~ /^\s*([a-z0-9_\:]+)\s*/i;

	# warn Dumper $self->{data};

	return $self;
}

sub name {
	my ($self) = @_;
	return $self->{data}{className};
}

sub data {
	my ($self) = @_;
	return $self->{data};
}

sub location {
	my ($self) = @_;
	my $p = $self->{file};
	$p =~ s|[/\\][^/\\]+$||;
	return $p;
}

sub libLocation {
	my ($self) = @_;
	my @chunks = split /::/, $self->name;
	pop @chunks;
	return join '/', @chunks;
}

1;
