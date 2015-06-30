package Eldhelm::Util::AsyncScript;

use strict;
use Data::Dumper;
use MIME::Base64 qw(decode_base64);

### UNIT TEST: 303_async_script.pl ###

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

1;
