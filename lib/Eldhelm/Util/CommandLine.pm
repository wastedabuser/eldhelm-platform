package Eldhelm::Util::CommandLine;

use strict;

sub parseArgv {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($arg, %opt);
	while ($arg = shift @_) {
		if ($arg =~ /^-+(\S+)/) {
			my $op = $1;
			if ($_[0] && $_[0] =~ /^-+\S+/) {
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

	my $opts = join "\n\t", map {
		join(" ", map { "-$_" } split(/ /, $_->[0]))." - ".join("; ", $_->[ 0 .. $#$_ ])
	} @{ $self->{options} };

	my $args;
	if ($opts) {
		$args = "[Options] ";
	}
	if ($self->{items}) {
		my $items = join("|", @{ $self->{items} });
		$args .= "[$items] ";
	}

	my $usage = "Usage:\n\tperl $0 $args\n";
	$usage .= "\nOptions:\n\t$opts\n" if $opts;
	return $usage;
}

sub arguments {
	my ($self) = @_;
	return Eldhelm::Util::CommandLine->parseArgv(@{ $self->{argv} });
}

1;
