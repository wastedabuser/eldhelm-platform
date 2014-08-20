package Eldhelm::Util::PlainCommunication;

use strict;
use IO::Socket;

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

1;
