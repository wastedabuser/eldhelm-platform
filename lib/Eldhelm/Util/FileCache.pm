package Eldhelm::Util::FileCache;

=pod

=head1 NAME

Eldhelm::Util::FileCache - A utility for caching content into temporary files.

=head1 SYNOPSIS

Displays the usage inside a controller action, please see L<Eldhelm::Basic::Controller>:

	my $handler    = $self->getHandler;
	my $sourcePath = 
		$handler->getPathFromUrl("/data/myFile.txt");
	
	my $cache = Eldhelm::Util::FileCache->new(
		cachePath  => $handler->getPathTmp("myFile.txt"),
		sourcePath => $sourcePath
	);
	
	unless ($cache->valid) {
		my $fileData;
		
		# do something cpu or disk intensive
		# .....
		
		$cache->cache($fileData);
	}
	
	$self->responseWrite($cache->content);

=head1 METHODS

=over

=cut

use strict;
use Data::Dumper;
use Carp;

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<cachePath> String - Full path and file name to the cache location;
C<sourcePath> String - Full path and file to the file source location;
C<relatedPaths> String - The file might exist in alternatiove locations not only in the C<sourcePath>;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = { relatedPaths => [], %args };
	bless $self, $class;

	return $self;
}

=item cache($content) self

Caches the provided content into a file. Uses C<cachePath> constructor argument.
Dies on error.

C<$content> String - The data to be cached;

=cut

sub cache {
	my ($self, $content) = @_;
	$self->{content} = $content;
	open FW, ">$self->{cachePath}" or confess "Unable to write file $self->{cachePath}: $!";
	print FW $content;
	close FW;
	return $self;
}

sub isModified {
	my ($self, $path) = @_;
	return (stat $self->{cachePath})[9] <= (stat $path)[9];
}

=item valid($path) 1 or undef

Checks whether the cache exists and whether it is modified recently.

C<$path> String - Optional; Path to a cached file; Defaults to C<cachePath> constructor argument;

=cut

sub valid {
	my ($self, $path) = @_;
	return unless -f $self->{cachePath};
	my $res;
	foreach ($self->{sourcePath}, @{ $self->{relatedPaths} }) {
		$res ||= $self->isModified($_);
	}
	return !$res;
}

=item content() String

Retrieves the cached file content.

=cut

sub content {
	my ($self) = @_;
	return $self->{content} if $self->{content};

	open FR, $self->{cachePath} or confess "Unable to read file $self->{cachePath}: $!";
	$self->{content} = join "", <FR>;
	close FR;

	return $self->{content};
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;