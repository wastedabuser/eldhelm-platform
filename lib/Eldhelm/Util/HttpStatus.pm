package Eldhelm::Util::HttpStatus;

use strict;

my %statuses = (
	200 => "OK",
	301 => "Moved Permanently",
	401 => "Unauthorized",
	403 => "Forbidden",
	404 => "Not Found",
	500 => "Internal Server Error",
);

sub getStatus {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($code) = @_;
	return "$code $statuses{$code}";
}

1;
