package Eldhelm::Util::Communication;

use strict;

use Data::Dumper;
use LWP::UserAgent;
use Eldhelm::Util::Url;
use Digest::MD5 qw(md5_hex);

sub simpleHttpRequest {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($url, $method) = @_;
	$method ||= "get";

	my $ua = LWP::UserAgent->new;
	if ($method eq "get") {
		$ua->default_header("Accept-Language" => "en-us,en;q=0.5");
		$ua->default_header("Accept-Charset"  => "ISO-8859-1,utf-8;q=0.7,*;q=0.7");
		$ua->default_header("User-Agent" => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:6.0) Gecko/20100101 Firefox/6.0");
		$ua->default_header("Accept"     => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
	}
	my $response = $ua->$method($url);

	if ($response->is_success) {
		return $response->content;
	} else {
		die $response->status_line;
	}
}

sub httpGetWithChecksum {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($host, $params, $secret) = @_;

	my @keys = keys %$params;
	$params->{checksum} = md5_hex(join "", $secret, map { $params->{$_} } @keys);
	$params->{checkprops} = join ",", @keys;

	my $url      = Eldhelm::Util::Url->new(uri => $host);
	my $ua       = LWP::UserAgent->new;
	my $reqUrl   = $url->compileWithParams($params);
	my $response = $ua->get($reqUrl);

	if ($response->is_success) {
		return $response->content;
	} else {
		die $response->status_line.": $reqUrl";
	}
}

sub acceptGetWithChecksum {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($params, $secret) = @_;

	my @keys = split /,/, $params->{checkprops};

	die "Invalid checksum: ".Dumper($params)
		if $params->{checksum} ne md5_hex(join "", $secret, map { $params->{$_} } @keys);

	return { map { +$_ => $params->{$_} } @keys };
}

1;
