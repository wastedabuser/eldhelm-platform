package Eldhelm::Util::PlainCommunication;

=pod

=head1 NAME

Eldhelm::Util::PlainCommunication - A utility for plain text communication via socket.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;
use IO::Socket;

=item send($host, $port, $message)

Will open a socket to C<$host:$port> and send a C<$message>. Then close the socket.
Dies if the socket could not be opened.

C<$host> String - Remote address;
C<$port> String - Remote port;
C<$message> String - The message to be sent;

=cut

sub send {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($host, $port, $message) = @_;

	my $remote = IO::Socket::INET->new(
		Proto    => 'tcp',
		PeerAddr => $host,
		PeerPort => $port,
		Reuse    => 1,
	) or die "$!";

	$remote->autoflush(1);
	print $remote $message;
	close $remote;
	
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
