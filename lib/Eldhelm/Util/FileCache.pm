package Eldhelm::Util::FileCache;

use strict;
use Data::Dumper;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	return $self;
}

sub cache {
	my ($self, $content) = @_;
	$self->{content} = $content;
	open FW, ">$self->{cachePath}" or confess "Unable to write file $self->{cachePath}: $!";
	print FW $content;
	close FW;
	return $self;
}

sub valid {
	my ($self) = @_;
	return unless -f $self->{cachePath};
	return (stat $self->{cachePath})[9] >= (stat $self->{sourcePath})[9];
}

sub content {
	my ($self) = @_;
	return $self->{content} if $self->{content};

	open FR, $self->{cachePath} or confess "Unable to read file $self->{cachePath}: $!";
	$self->{content} = join "", <FR>;
	close FR;

	return $self->{content};
}

1;
