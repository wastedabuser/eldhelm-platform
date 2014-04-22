package Eldhelm::Util::MachineInfo;

use strict;
use Carp;

sub isWin {
	return $^O =~ m/mswin/i;
}

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

1;