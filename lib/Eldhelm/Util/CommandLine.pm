package Eldhelm::Util::CommandLine;

=pod

=head1 NAME

Eldhelm::Util::CommandLine - A utility class for parsing script arguments.

=head1 SYNOPSIS

	use strict;
	use Eldhelm::Util::CommandLine;
	
	my $cmd = Eldhelm::Util::CommandLine->new(
		argv    => \@ARGV,
		items   => [ 'exmplain what should be listed here' ],
		options => [
			[ 'h help', 'this help text' ],
			[ 'o', 'other example option']
		]
	);
	
	my %args = $cmd->arguments;
	
	if ($args{h} || $args{help}) {
		print $cmd->usage;
		exit;
	}
	
	# something useful here ...

This script can be called this way then:
C<perl myscript.pl item1 item2 item3 -o something>

To see the help you type:
C<perl myscript.pl -h> or C<perl myscript.pl -help>

=head1 METHODS

=over

=cut

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

=item new(%args)

Constructs a new object.

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	return bless $self, $class;
}

=item usage() String

Returns a stream of the help text ready to be printed in the terminal.

=cut

sub usage {
	my ($self) = @_;

	my $opts = join "\n\t", map {
		join(" ", map { "-$_" } split(/ /, $_->[0]))." - ".join("; ", @{$_}[ 1 .. $#$_ ])
	} @{ $self->{options} };

	my $args = "";
	if ($self->{items}) {
		my $items = join("|", @{ $self->{items} });
		$args .= "[$items] ";
	}
	if ($opts) {
		$args .= "[Options] ";
	}

	my $usage = "Usage:\n\tperl $0 $args\n";
	$usage .= "\nOptions:\n\t$opts\n" if $opts;

	if ($self->{examples}) {
		my $examples = join("\n", map { "\t".$_ } @{ $self->{examples} });
		$usage .= "\nExamples:\n$examples\n";
	}

	return $usage;
}

=item arguments() Hash

Returns a Hash of parsed arguments.

=cut

sub arguments {
	my ($self) = @_;
	return Eldhelm::Util::CommandLine->parseArgv(@{ $self->{argv} });
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
