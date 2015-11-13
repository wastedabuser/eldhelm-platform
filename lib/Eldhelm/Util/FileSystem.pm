package Eldhelm::Util::FileSystem;

=pod

=head1 NAME

Eldhelm::Util::FileSystem - A utility class for file system interaction.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;
use Carp;

=item readFoldersList($path)

Returns the list of folders from the folder specified.

C<$path> String - The path to the folder to be examined

=cut

sub readFoldersList {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($path) = @_;
	$path ||= './';
	opendir DIR, $path or confess "Can not open dir '$path': $!";
	my @dirs = map { join '/', $path || (), $_ } grep { $_ !~ /^\./ && -d join('/', $path || (), $_) } readdir DIR;
	closedir DIR;
	return @dirs;
}

=item readFileList($path) Array

Returns the list of files recursively from the folder specified.

C<$path> String - The path to the folder to be examined

=cut

sub readFileList {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($path) = @_;
	$path ||= './';
	opendir DIR, $path or confess "Can not open dir '$path': $!";
	my @list = map { join '/', $path || (), $_ } grep { $_ !~ /^\./ } readdir DIR;
	my @files = grep { -f $_ } @list;
	my @dirs = grep { -d $_ } @list;
	closedir DIR;
	return @files, map { readFileList($_) } @dirs;
}

=item getFileContents($path) String

Reads a file and returns its contents.

C<$path> String - The file to be read.

=cut

sub getFileContents {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($path) = @_;
	open my $fr, $path or confess "Can not read '$path': $!";
	my $content = do { local $/ = undef; <$fr> };
	close $fr;
	return $content;
}

=item writeFileContents($path)

Writes data to a file.

C<$path> String - The file to be written.
C<$contents> String - The data to be written.

=cut

sub writeFileContents {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($path, $content) = @_;
	open my $fw, '>', $path or confess "Can not write '$path': $!";
	print $fw $content;
	close $fw;
	return;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;