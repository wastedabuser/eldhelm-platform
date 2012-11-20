package Eldhelm::Server::Handler::Http;

use strict;
use Eldhelm::Util::Mime;
use Eldhelm::Util::HttpStatus;
use Eldhelm::Util::Tool;
use Data::Dumper;
use Date::Format;

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

	my %parsed;
	my @chunks = split /\r\n/, $data;

	(shift @chunks) =~ m~^([a-z]+)\s+/(.*?)\s+http/(.*)~i;
	$parsed{method} = uc($1);
	(my $url = $2) =~ s|\.+/||g;
	my @parts = split /\?/, $url;
	$parsed{url}         = shift @parts;
	$parsed{queryString} = join "?", @parts;
	$parsed{version}     = $3;

	foreach (@chunks) {
		if (m/^(.*?)\s*:\s*(.*)$/) {
			$parsed{headers}{$1} = $2;
		} else {
			$parsed{content} .= $_;
		}
	}

	my $ln = $parsed{len} = $parsed{headers}{"Content-Length"} || -1;
	$parsed{len} -= length $parsed{content} if $ln > 0;

	return (\%parsed, "");
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

	foreach (qw(documentRoot directoryIndex rewriteUrl statusHandlers)) {
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
}

sub parseContent {
	my ($self, $content) = @_;
	$self->parsePost($content);
	$self->parseGet($self->{queryString});
	$self->worker->log("$self->{method} $self->{url}", "access");
}

sub parseGet {
	my ($self, $str) = @_;
	$self->{get} = { %{ $self->{get} }, %{ $self->parseParams($str) } };
	return $self;
}

sub parsePost {
	my ($self, $str) = @_;
	$self->{post} = $self->parseParams($str);
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

sub createResponse {
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

		if (!$cont && $router->hasErrors) {
			$cont = $self->createStatusResponse(500, $router->getErrors);
		} else {
			$self->addHeaders(@$headers);
		}
		$self->{contentType} ||= "text/html";
	} else {
		my $path = "$self->{documentRoot}/$url";
		$path .= ($path =~ m|/$| ? "" : "/")."$self->{directoryIndex}" if -d $path;
		$cont                = $self->readDocument($path);
		$cont                = $self->createStatusResponse(404, $path) if !$cont;
		$self->{contentType} = Eldhelm::Util::Mime->getMime($path);
	}
	return $self->createHttpResponse($cont);
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
	if ($self->{rewriteUrl}) {
		foreach (@{ $self->{rewriteUrl} }) {
			if (!$_->[0] && !$url) {
				$url = $_->[1];
				last;
			}
			next if !$_->[0];
			if (my @matches = $url =~ /$_->[0]/) {
				$url = eval "qq~$_->[1]~";
				$self->parseGet(eval "qq~$_->[2]~") if $_->[2];
				last;
			}
		}
	}
	return $url;
}

sub createStatusResponse {
	my ($self, $code, @args) = @_;
	$self->{status} = Eldhelm::Util::HttpStatus->getStatus($code);

	my ($handles, $headers, $cont) = ($self->{statusHandlers});
	if ($handles) {
		foreach (@$handles) {
			next if $code !~ m/$_->[0]/;
			($headers, $cont) = $self->routeAction(@$_[ 1 .. 2 ], @args);
			last;
		}
	}

	my $fn = "_default${code}Response";
	$cont = $self->$fn(@args) if !$cont && $self->can($fn);
	return $cont || $self->{status};
}

sub createUnauthorizedResponse {
	my ($self, $controller) = @_;
	return $self->createStatusResponse(401);
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

sub createHttpResponse {
	my ($self, $cont) = @_;
	my $info    = $self->worker->{info};
	my @headers = (
		"HTTP/1.0 $self->{status}",
		"Server: Eldhelm Server $info->{version} ($^O)",
		"Content-Length: ".length($cont),
		$self->{contentType} ? "Content-Type: $self->{contentType}" : (),
		@{ $self->{responseHeaders} }, "\r\n",
	);
	return join("\r\n", @headers).($self->{method} ne "HEAD" ? $cont : "");
}

sub readDocument {
	my ($self, $path) = @_;
	my $data = $self->SUPER::readDocument($path);
	if ($data) {
		my $time = (stat($path))[9];

		# $self->addHeaders("Last-Modified: ".time2str("%a, %e %b %Y %T GMT", $time));
	}
	return $data;
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

1;
