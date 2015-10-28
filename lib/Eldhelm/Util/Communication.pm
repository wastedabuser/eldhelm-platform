package Eldhelm::Util::Communication;

=pod

=head1 NAME

Eldhelm::Util::Communication - A utility for making http requests;

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;

use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use Eldhelm::Util::Url;
use Eldhelm::Server::Parser::Json;
use Digest::MD5 qw(md5_hex);

=item simpleHttpRequest($url, $method) String

Creates an http request and retrieves the content. 
Indicates itslef with User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64; rv:6.0) Gecko/20100101 Firefox/6.0
Dies on error.

C<$url> String - The url;
C<$method> String - Optional; The request method; Defaults to get;

=cut

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

	return loadUrl($url, {}, $method, $headers);
}

### UNIT TEST: 300_communication.pl ###

=item loadUrl($url, $args, $method, $headers) String

Loads content from an url.
Dies on error.

C<$url> String - The url;
C<$args> HashRef - Optional; Arguments to be added to the url;
C<$method> String - Optional; The request method; Defaults to get;
C<$headers> Hashref - Optional; Additional headers to be added;

=cut

sub loadUrl {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($url, $args, $method, $headers) = @_;
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

=item submitToUrl($url, $args, $method, $headers) String

Posts content to an url.
Dies on error.

C<$url> String - The url;
C<$args> HashRef - Optional; Arguments to be added to the url;
C<$method> String - Optional; The request method; Defaults to post;
C<$content> String - Optional; The content to be posted;
C<$headers> Hashref - Optional; Additional headers to be added;

=cut

sub submitToUrl {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($url, $args, $method, $content, $headers) = @_;
	$method ||= "post";

	$url = Eldhelm::Util::Url->new(uri => $url)->compileWithParams($args) if $args;

	my $req = HTTP::Request->new($method, $url);
	if ($headers) {
		$req->header(%$headers);
	}
	if ($content) {
		$req->content($content);
	}

	my $ua       = LWP::UserAgent->new;
	my $response = $ua->request($req);
	if ($response->is_success) {
		return $response->content;
	} else {
		die $response->status_line.": $url";
	}
}

=item loadJson($url, $args, $method, $headers) String

Same as loadUrl except id parses the response content as JSON.
Dies on error.

C<$url> String - The url;
C<$args> HashRef - Optional; Arguments to be added to the url;
C<$method> String - Optional; The request method; Defaults to get;
C<$headers> Hashref - Optional; Additional headers to be added;

=cut

sub loadJson {
	return Eldhelm::Server::Parser::Json->parse(loadUrl(@_));
}

=item httpGetWithChecksum($host, $params, $secret) String

Sends a and http request via get. Adds and md5 checksum parameter compiled of the properties in C<$params>.
Dies on error.

C<$host> String - The host url;
C<$params> HashRef - Arguments to be added to the url;
C<$secret> String - A tokken to be added when creating the checksum

=cut

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

=item acceptGetWithChecksum($params, $secret) HashRef

Decodes a request created with C<httpGetWithChecksum>. Returns a HashRef of properties that are verified against the checksum.
Dies on error.

C<$params> HashRef - Arguments to be added to the url;
C<$secret> String - A tokken to be added when creating the checksum

=cut

sub acceptGetWithChecksum {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($params, $secret) = @_;

	my @keys = split /,/, $params->{checkprops};

	die "Invalid checksum: ".Dumper($params)
		if $params->{checksum} ne md5_hex(join "", $secret, map { $params->{$_} } @keys);

	return { map { +$_ => $params->{$_} } @keys };
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
