package Eldhelm::Util::MachineInfo;

=pod

=head1 NAME

Eldhelm::Util::MachineInfo - A utility for getting machine related info.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;
use Carp;

=item isWin() 1 or undef

Checks whether the machine is running Windows.

=cut

sub isWin {
	return $^O =~ m/mswin/i;
}

=item ip($host) Array

Returns a list of the current machine ip addresses.

C<$host> String - A host or instruction.

In fact it parses the addresses.
Uses C<ipconfig> on Windows and C<ifconfig> on Linux.
On linux you can specify an interface like this.

	Eldhelm::Util::MachineInfo->ip('auto:eth0');

Dies if unable to retrieve any ip.

=cut

sub ip {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($host) = @_;
	
	my @ip;
	if (isWin) {
		@ip = `ipconfig` =~ m/IPv4 Address.+:\s([\d\.]+)/g;
	} else {
		my ($iface) = $host =~ /auto:?(.*)/;
		@ip = `ifconfig $iface` =~ m/inet addr:([\d\.]+)/g;
	}
	
	confess("Unable to get ip for $host") unless @ip;
	
	return @ip;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;