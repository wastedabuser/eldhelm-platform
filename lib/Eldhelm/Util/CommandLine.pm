package Eldhelm::Util::CommandLine;

use Data::Dumper;

# this static method is deprecated
sub parseArgv {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($arg, %opt);
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
		if ($arg) {
			$opt{list} ||= [];
			push @{ $opt{list} }, $arg;
		}
	}
	return %opt;
}

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	return bless $self, $class;
}

sub usage {
	my ($self) = @_;

	my $opts = join "\n\t", map { "-".join(" - ", @$_) } @{ $self->{usage} };

	return qq~Usage:
perl $0 [list of items or options]\n
Options:
	$opts
\n~;

}

sub arguments {
	my ($self) = @_;
	my %opt;
	$opt{list} = [];
	while (my $arg = shift @{ $self->{argv} }) {
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
