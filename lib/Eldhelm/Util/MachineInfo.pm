package Eldhelm::Util::MachineInfo;

use carp;

my ($currentFh, $isWin);

sub isWin {
	return $^O =~ m/mswin/i;
}

sub ip {
	my ($self, $host) = @_;
	
	my $ip;
	if (isWin) {
		($ip) = `ipconfig` =~ m/IPv4 Address.+:\s([\d\.]+)/;
	} else {
		my ($iface) = $host =~ /auto:(.+)/;
		($ip) = `ifconfig $iface` =~ m/addr:([\d\.]+)/;
	}
	
	confess("Unable to get ip for $host") unless $ip;
	
	return $ip;
}

1;