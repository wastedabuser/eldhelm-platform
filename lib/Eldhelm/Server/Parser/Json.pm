package Eldhelm::Server::Parser::Json;

use strict;
use JSON;
use Encode qw();
use Eldhelm::Util::Tool;
use Carp;

my $json = JSON->new;
$json->allow_blessed(1);

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	Encode::_utf8_on($data);
	my $ret = $json->decode($data);
	return Eldhelm::Util::Tool::utfFlagDeep($ret, 0);
}

sub encode {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	my $ret = $json->encode(Eldhelm::Util::Tool::utfFlagDeep($data, 1));
	Encode::_utf8_off($ret);
	return $ret;
}

sub compose {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data, $options) = @_;
	my ($jsn, $ln);
	$jsn = encode($data) if $data;
	{
		use bytes;
		$ln = length($jsn) || 0;
	}
	my %headers = (
		contentLength => $ln,
		$options ? %$options : (),
	);
	return '["eldhlem-json-1.1",'.encode(\%headers).']'.$jsn;
}

sub encodeFixNumbers {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	my $string = encode($data);
	$string =~ s/"(\d+\.?\d*)"/$1/g;
	return $string;
}

1;
