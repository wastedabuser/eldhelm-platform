package Eldhelm::Server::Handler;

use strict;
use Data::Dumper;
use Eldhelm::Server::Session;
use Carp;

sub proxyPossible {
	shift @_ if $_[0] eq __PACKAGE__;
	return;
}

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	return $self;
}

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

sub router {
	my ($self) = @_;
	return $self->{worker}->router;
}

sub setConnection {
	my ($self, $conn) = @_;
	$conn->set("composer", $self->{composer});
	$self->{connection} = $conn;
}

sub getConnection {
	my ($self) = @_;
	return $self->{connection};
}

sub handle {
	my ($self) = @_;
	$self->parseContent($self->{content});
	return;
}

sub parseContent {
	my ($self, $content) = @_;
	return;
}

sub respond {
	my ($self) = @_;
	return;
}

sub createUnauthorizedResponse {
	my ($self, $controller) = @_;
	return;
}

sub createErrorResponse {
	my ($self, $controller) = @_;
	return;
}

sub finish {
	my ($self) = @_;
	return;
}

sub log {
	my $self = shift;
	$self->{worker}->log(@_);
	return $self;
}

sub debug {
	my $self = shift;
	$self->{worker}->debug(@_);
	return $self;
}

sub access {
	my $self = shift;
	$self->{worker}->access(@_);
	return $self;
}

sub error {
	my $self = shift;
	$self->{worker}->error(@_);
	return $self;
}

sub readDocument {
	my ($self, $path) = @_;
	if (-f $path) {
		my $buf;
		eval {
			$self->access("Open '$path'");
			open FILE, $path or confess $!;
			binmode FILE;
			my $data;
			while (read(FILE, $data, 4) != 0) {
				$buf .= $data;
			}
			close FILE or confess $!;
			$self->access("File '$path' is ".length($buf));
		};
		$self->error("Error reading file: $@") if $@;
		return $buf;
	}
}

sub getPathTmp {
	my ($self, $url) = @_;
	$self->getPathFromUrl($self->worker->getConfig("server.tmp"), $url);
}

sub getPathFromUrl {
	my ($self, $folder, $url) = @_;
	unless ($url) {
		$url = $folder;
		$folder = $self->{documentRoot};
	}
	$url =~ s|^/+||;
	$url =~ s/[^\w\.\!\?\/\-]//g;
	$url =~ s/\.{2,}//g;
	return "$folder/$url";
}

sub readDocumentUrl {
	my ($self, $url) = @_;
	return $self->readDocument($self->getPathFromUrl($url));
}

1;
