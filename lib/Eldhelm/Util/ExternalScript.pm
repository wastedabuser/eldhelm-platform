package Eldhelm::Util::ExternalScript;

=pod

=head1 NAME

Eldhelm::Util::ExternalScript - A utility for writing for parsing machine generated external script arguments.

=head1 SYNOPSIS

Please see: 
L<< Eldhelm::Server::Worker->runExternalScript >> and
L<< Eldhelm::Server::Worker->runExternalScriptAsync >>

	use strict;
	
	use lib "../lib";
	use lib "../../lib";
	use Eldhelm::Util::ExternalScript;
	
	my $configPath = shift @ARGV;
	my ($data) = Eldhelm::Util::ExternalScript->argv(@ARGV);
	
	# do something usefull here ...
	
	# finally send back some results
	# makes sence only if the script is synced!
	Eldhelm::Util::ExternalScript->output('Result');

Or call it like this.	

	Eldhelm::Util::ExternalScript->output({
		a => 1,
		b => 2
	});

You should call C<output> only once!

=head1 METHODS

=over

=cut

use strict;
use Data::Dumper;
use MIME::Base64 qw(encode_base64 decode_base64);

### UNIT TEST: 303_external_script.pl ###

=item argv(@argv) 

Parses the @ARGV of a perl script.

C<@argv> Array - The @ARGV.

=cut

sub argv {
	shift @_ if $_[0] eq __PACKAGE__;
	return map { parseArg($_) } @_;
}

sub parseArg {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($arg) = @_;
	my $data = decode_base64($arg);
	return eval $data;
}

sub encodeArgv {
	shift @_ if $_[0] eq __PACKAGE__;
	return map { encodeArg($_) } @_;
}

sub encodeArg {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($arg) = @_;
	local $Data::Dumper::Terse = 1;
	return encode_base64(Dumper($arg), "");
}

=item output($data)

Outputs data to be parsed by the executing worker.

C<$data> Mixed - Data to be outputed.

=cut

sub output {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($arg) = @_;
	if (ref $arg) {
		local $Data::Dumper::Terse = 1;
		print Dumper($arg);
		return;
	}
	print $arg;
	return;
}

sub parseOutput {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($arg) = @_;
	if ($arg =~ /^[\{\[]/) {
		return eval $arg;
	}
	return $arg;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;