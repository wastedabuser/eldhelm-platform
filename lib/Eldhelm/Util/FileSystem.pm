package Eldhelm::Util::FileSystem;

use strict;
use Carp;

sub readFoldersList {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($path) = @_;
	$path ||= "./";
	opendir DIR, $path or confess "Can not open dir '$path': $@";
	my @dirs = map { join "/", $path || (), $_ } grep { $_ !~ /^\./ && -d join("/", $path || (), $_) } readdir DIR;
	closedir DIR;
	return @dirs;
}

sub readFileList {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($path) = @_;
	$path ||= "./";
	opendir DIR, $path or confess "Can not open dir '$path': $@";
	my @list = map { join "/", $path || (), $_ } grep { $_ !~ /^\./ } readdir DIR;
	my @files = grep { -f $_ } @list;
	my @dirs = grep { -d $_ } @list;
	closedir DIR;
	return @files, map { readFileList($_) } @dirs;
}

sub getFileContents {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($path) = @_;
	open FR, $path or confess "Can not open file '$path': $@";
	my $content = join "", <FR>;
	close FR;
	return $content;
}

1;