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
	my @files = map { join "/", $path || (), $_ } grep { $_ !~ /^\./ && -f join("/", $path || (), $_) } readdir DIR;
	closedir DIR;
	return @files;
}

1;