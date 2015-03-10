package Eldhelm::Util::Communication;

use strict;

use Data::Dumper;
use LWP::UserAgent;
use Eldhelm::Util::Url;
use Eldhelm::Server::Parser::Json;
use Digest::MD5 qw(md5_hex);

sub simpleHttpRequest {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($url, $method) = @_;
	$method ||= "get";

	my $headers;
	$headers = {
		"Accept-Language" => "en-us,en;q=0.5",
		"Accept-Charset"  => "ISO-8859-1,utf-8;q=0.7,*;q=0.7",
		"User-Agent"      => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:6.0) Gecko/20100101 Firefox/6.0",
		"Accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
		}
		if $method eq "get";

	return loadUrl($url, {}, $method, undef, $headers);
}

sub loadUrl {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($url, $args, $method, $content, $headers) = @_;
	$method ||= "get";

	$url = Eldhelm::Util::Url->new(uri => $url)->compileWithParams($args) if $args;

	my $ua = LWP::UserAgent->new;
	if ($headers) {
		$ua->default_header($_ => $headers->{$_}) foreach keys %$headers;
	}

	my $response = $ua->$method($url);
	if ($response->is_success) {
		return $response->content;
	} else {
		die $response->status_line.": $url";
	}
}

sub loadJson {
	return Eldhelm::Server::Parser::Json->parse(loadUrl(@_));
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
