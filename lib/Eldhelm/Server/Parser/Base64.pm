package Eldhelm::Server::Parser::Base64;

use strict;
use JSON;
use MIME::Base64 qw(encode_base64 decode_base64);
use Encode qw();
use Eldhelm::Util::Tool;
use Carp;

my $json = JSON->new;
$json->allow_blessed(1);

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	$data = decode_base64($data);
	Encode::_utf8_on($data);
	my $ret = $json->decode($data);
	return Eldhelm::Util::Tool->utfFlagDeep($ret, 0);
}

sub encode {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;

	# my $ret = $json->encode(Eldhelm::Util::Tool->utfFlagDeep($data, 1));
	# Encode::_utf8_off($ret);
	# return encode_base64($ret);
	return encode_base64(Eldhelm::Util::Tool->jsonEncode($data), "");
}

sub compose {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data, $options) = @_;
	my ($payload, $ln);
	$payload = encode($data) if $data;
	{
		use bytes;
		$ln = length($payload) || 0;
	}
	my %headers = (
		contentLength => $ln,
		$options ? %$options : (),
	);
	return "BASE64ELDHELM02".encode(\%headers)."PAYLOAD".$payload;
}

1;
