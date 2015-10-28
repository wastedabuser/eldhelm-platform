package Eldhelm::Util::HttpStatus;

=pod

=head1 NAME

Eldhelm::Util::HttpStatus - A utility for HTTP status messages.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;

my %statuses = (
	200 => "OK",
	301 => "Moved Permanently",
	401 => "Unauthorized",
	403 => "Forbidden",
	404 => "Not Found",
	500 => "Internal Server Error",
);

=item getStatus($code) String

Returns a http status message with its associated code.

C<$code> String - The http status code; 

=cut

sub getStatus {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($code) = @_;
	return "$code $statuses{$code}";
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
