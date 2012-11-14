package Eldhelm::Util::CommandLine;

use Data::Dumper;

sub parseArgv {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($arg, %opt);
	$opt{list} = [];
	while ($arg = shift @_) {
		if ($arg =~ /^-+(\S+)/) {
			my $op = $1;
			if ($_[0] =~ /^-+\S+/) {
				$opt{$op} = 1;
				next;
			}
			$opt{$op} = shift(@_) || 1;
			next;
		}
		push @{ $opt{list} }, $arg;
	}
	return %opt;
}

1;
