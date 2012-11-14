package Eldhelm::Util::Communication;

use strict;
use LWP::UserAgent;

sub simpleHttpGetRequest {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($url) = @_;
	my $ua = LWP::UserAgent->new;
	$ua->default_header("Accept-Language" => "en-us,en;q=0.5");
	$ua->default_header("Accept-Charset"  => "ISO-8859-1,utf-8;q=0.7,*;q=0.7");
	$ua->default_header("User-Agent"      => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:6.0) Gecko/20100101 Firefox/6.0");
	$ua->default_header("Accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
	my $response = $ua->get($url);

	if ($response->is_success) {
		return $response->content;
	} else {
		die $response->status_line;
	}
}

1;