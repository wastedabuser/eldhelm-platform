package Eldhelm::Server::Handler::Http;

use strict;
use Eldhelm::Util::Mime;
use Eldhelm::Util::HttpStatus;
use Eldhelm::Server::Parser::Json;
use Eldhelm::Util::Tool;
use Data::Dumper;
use Date::Format;
use Eldhelm::Util::Factory;

use base qw(Eldhelm::Server::Handler);

# static methods

sub check {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	return $data =~ m/^(?:GET|POST|HEAD)/ ? 1 : undef;
}

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;

	return ({ len => -2 }, $data) unless $data =~ /\r\n\r\n/;

	my @chunks = split /\r\n/, $data;
	my $fl = shift @chunks;
	my %parsed = (headerContent => "$fl\r\n");
	$fl =~ m~^([a-z]+)\s+/(.*?)\s+http/(.*)~i;
	$parsed{method} = uc($1);
	(my $url = $2) =~ s|\.+/||g;
	my @parts = split /\?/, $url;
	$parsed{url}         = shift @parts;
	$parsed{queryString} = join "?", @parts;
	$parsed{version}     = $3;

	foreach (@chunks) {
		if (m/^(.*?)\s*:\s*(.*)$/) {
			$parsed{headers}{$1} = $2;
			$parsed{headerContent} .= "$_\r\n";
		} else {
			$parsed{content} .= $_;
		}
	}
	$parsed{headerContent} .= "\r\n";

	my $ln = $parsed{len} = $parsed{headers}{"Content-Length"} || -1;
	$parsed{len} -= length $parsed{content} if $ln > 0;

	return (\%parsed, "");
}

sub proxyPossible {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($parsed, $urls) = @_;
	foreach (@$urls) {
		return $_->[1] if $parsed->{url} =~ m($_->[0])i;
	}
	return 1;
}

# the class definition

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Handler->new(%args);
	$self->{status} = Eldhelm::Util::HttpStatus->getStatus(200);
	$self->{headers}         ||= {};
	$self->{responseHeaders} ||= [];
	$self->{get}             ||= {};
	$self->{post}            ||= {};
	bless $self, $class;

	$self->init;

	return $self;
}

sub init {
	my ($self) = @_;

	my $host = $self->{headers}{Host};
	$host =~ s/^www\.//;
	$self->{host} = $host;

	my $httpConfig = $self->worker->getConfig("server.http");
	my $hostConfig = $httpConfig->{host}{ $self->{host} };

	foreach (qw(documentRoot directoryIndex rewriteUrl rewriteUrlCache statusHandlers)) {
		my $prop = $httpConfig->{$_};
		if (!$hostConfig || !$hostConfig->{$_}) {
			$self->{$_} = $prop;
			next;
		}
		my $hostProp = $hostConfig->{$_};
		if (ref $prop eq "HASH") {
			$self->{$_} = Eldhelm::Util::Tool->merge({}, $prop, $hostProp);
		} elsif (ref $prop eq "ARRAY" && $hostProp) {
			$self->{$_} = [ @$hostProp, @$prop ];
		} else {
			$self->{$_} = $hostProp || $prop;
		}
	}

	$self->{urlCache} = $self->worker->{urlCache}{$host} ||= {} if $self->{rewriteUrlCache};
}

sub parseContent {
	my ($self, $content) = @_;
	my $ct = $self->{headers}{'Content-Type'};
	if ($ct =~ m|application/x-www-form-urlencoded|) {
		$self->parsePostUrlencoded($content);
	} elsif ($ct =~ m|application/json|) {
		$self->parsePostJson($content);
	}
	$self->parseGet($self->{queryString});
	$self->parseCookies($self->{headers}{Cookie}) if $self->{headers}{Cookie};
	$self->worker->log("$self->{method} $self->{url}", "access");
}

sub parseGet {
	my ($self, $str) = @_;
	$self->{get} = { %{ $self->{get} }, %{ $self->parseParams($str) } };
	return $self;
}

sub parsePostUrlencoded {
	my ($self, $str) = @_;
	$self->{post} = $self->parseParams($str);
	return $self;
}

sub parsePostJson {
	my ($self, $str) = @_;
	eval { $self->{json} = Eldhelm::Server::Parser::Json->parse($str); };
	$self->worker->log("Unable to parse json: $@ Headers: ".Dumper($self->{headers})."Content: $str", "error") if $@;
	return $self;
}

sub parseCookies {
	my ($self, $str) = @_;
	my (%params, @list);
	foreach (split /\;\s*/, $str) {
		my ($name, $value) = split /\=/, $_;
		if (!$value && $_ !~ /\=/) {
			$value = $name;
			$name  = "";
		}

		# $value =~ tr/+/ /;
		# $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
		if ($name) {
			$params{$name} = $value;
		} else {
			push @list, $value;
		}
	}
	$self->{cookies}      = \%params;
	$self->{cookieValues} = \@list;
	return $self;
}

sub parseParams {
	my ($self, $data) = @_;
	my %params;
	foreach (split /\&/, $data) {
		my ($name, $value) = split /\=/, $_;
		$value =~ tr/+/ /;
		$value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
		$params{$name} = $value;
	}
	return \%params;
}

sub respond {
	my ($self) = @_;
	my $url = $self->rewriteUrl($self->{url});
	my ($headers, $contents, $cont);

	if (my @m = $url =~ /^controller:(.+)$/) {
		my $router = $self->router;

		# create isntance to update the timeout
		$self->worker->getPersist($self->{get}{sessionId})
			if $self->{get}{sessionId};

		($headers, $contents) = $self->routeAction($m[0]);
		$cont = join "", @$contents;

		$self->addHeaders(@$headers) unless $router->hasErrors;
		$self->{contentType} ||= "text/html";
		$self->worker->sendData($self->createHttpResponse($cont, length $cont));
		return;
	}

	my $path = $self->getPathFromUrl($url);
	$path .= ($path =~ m|/$| ? "" : "/")."$self->{directoryIndex}" if -d $path;
	unless (-f $path) {
		$cont = $self->createStatusResponse(404, $path);
		$self->{contentType} ||= "text/html";
		$self->worker->sendData($self->createHttpResponse($cont, length $cont));
		return;
	}

	$self->{contentType} = Eldhelm::Util::Mime->getMime($path);
	my $ln = -s $path;
	return $self->worker->sendFile($self->createHttpResponse("", $ln), $path, $ln);
}

sub routeAction {
	my ($self, $action, @args) = @_;
	return $self->router->route(
		$self->{headers},
		{   action    => $action,
			data      => { %{ $self->{get} }, %{ $self->{post} }, },
			sessionId => $self->{get}{sessionId},
		}
	);
}

sub rewriteUrl {
	my ($self, $url) = @_;

	my $origUrl = $url;
	if ($self->{urlCache} && $self->{urlCache}{$origUrl}) {
		my $cache = $self->{urlCache}{$origUrl};
		%{ $self->{get} } = %{ $cache->[1] };
		return $cache->[0];
	}

	if ($self->{rewriteUrl}) {
		foreach (@{ $self->{rewriteUrl} }) {
			if (!$_->[0] && !$url) {
				$url = $_->[1];
				$self->parseGet(eval "qq~$_->[2]~") if $_->[2];
				last;
			}
			next if !$_->[0];
			if (my @matches = $url =~ /$_->[0]/) {
				$url = eval("qq~$_->[1]~") if $_->[1];
				$self->parseGet(eval "qq~$_->[2]~") if $_->[2];
				last;
			}
		}
	}

	$self->{urlCache}{$origUrl} = [ $url, { %{ $self->{get} } } ]
		if $self->{urlCache};

	return $url;
}

sub createStatusResponse {
	my ($self, $code, @args) = @_;
	$self->{status} = Eldhelm::Util::HttpStatus->getStatus($code);

	my ($handles, $headers, $content) = ($self->{statusHandlers});
	if ($handles) {
		foreach (@$handles) {
			next if $code !~ m/$_->[0]/;
			my $contentParts;
			($headers, $contentParts) = $self->routeAction(@$_[ 1 .. 2 ], @args);
			$content = join "", @$contentParts;
			last;
		}
	}

	my $fn = "_default${code}Response";
	$content = $self->$fn(@args) if !$content && $self->can($fn);
	return $content || $self->{status};
}

sub createUnauthorizedResponse {
	my ($self, $controller) = @_;
	return $self->createStatusResponse(401);
}

sub createErrorResponse {
	my ($self, $controller) = @_;
	return $self->createStatusResponse(500, $self->router->getErrors);
}

sub redirect {
	my ($self, $url) = @_;
	$self->{status} = Eldhelm::Util::HttpStatus->getStatus(301);
	$self->addHeaders("Location: $url");
	return $self;
}

sub redirectNoCache {
	my ($self, $url) = @_;
	return $self->redirect($url)->addHeaders("Cache-Control: no-cache, must-revalidate");
}

sub addHeaders {
	my ($self, @headers) = @_;
	push @{ $self->{responseHeaders} }, @headers
		if @headers;
	return $self;
}

sub setCookie {
	my ($self, $name, $value, $args) = @_;

	my @chunks = ("$name=$value");
	if ($args) {
		push @chunks, "expires=".time2str("%a, %d %b %Y %T GMT", time + $args->{expires})
			if $args->{expires};
		push @chunks, "domain=$args->{domain}" if $args->{domain};
		push @chunks, "path=$args->{path}"     if $args->{path};
		push @chunks, "secure"                 if $args->{secure};
	}

	my $cookie = join "; ", @chunks;
	return $self unless $cookie;

	$self->addHeaders("Set-Cookie: $cookie");
	return $self;
}

sub createHttpResponse {
	my ($self, $cont, $ln) = @_;
	my $info    = $self->worker->{info};
	my @headers = (
		"HTTP/1.0 $self->{status}",
		"Server: Eldhelm Server $info->{version} ($^O)",
		"Content-Length: $ln",
		$self->{contentType} ? "Content-Type: $self->{contentType}" : (),
		@{ $self->{responseHeaders} }, "\r\n",
	);
	return join("\r\n", @headers).($self->{method} ne "HEAD" ? $cont : "");
}

sub getCookie {
	my ($self, $name) = @_;
	return unless $self->{cookies};
	return $self->{cookies}{$name};
}

sub finish {
	my ($self) = @_;
	$self->worker->endTask;

	# if !$self->{headers}{Connection} eq "keep-alive";
}

# ============================
# Some default status implementations
# ============================

sub _default404Response {
	my ($self, $path) = @_;
	$self->error("File '$path' not found");
	return;
}

sub _default500Response {
	my ($self, @data) = @_;
	return "<pre>".Dumper(@data)."</pre>";
}

# ============================
# File access api
# ============================

sub getPathFromUrl {
	my ($self, $url) = @_;
	return Eldhelm::Util::Factory->getAbsoluteClassPath($self->validatePath($url), "/Eldhelm/Application/www", $self->{documentRoot});
}

sub readDocumentUrl {
	my ($self, $url) = @_;
	return $self->readDocument($self->getPathFromUrl($url));
}

1;
