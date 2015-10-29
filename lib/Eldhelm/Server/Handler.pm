package Eldhelm::Server::Handler;

=pod

=head1 NAME

Eldhelm::Server::Handler - A base class for all protocol parsers/handlers.

=head1 SYNOPSIS

Handler classes are created by the server, you should not instantiate them yourself.

Displays the usage inside a controller action, please see L<Eldhelm::Basic::Controller>:

	# Example 
	# accesing the object
	# and using a method 
	$self->handler->getPathTmp('/file.temp');

=head1 METHODS

=over

=cut

use strict;
use Data::Dumper;
use Eldhelm::Util::Factory;
use Carp;

sub proxyPossible {
	shift @_ if $_[0] eq __PACKAGE__;
	return 1;
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
	$conn->set('composer', $self->{composer});
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
	my ($self, $controller, $message) = @_;
	return;
}

sub finish {
	my ($self) = @_;
	return;
}

sub stop {
	my ($self, $value) = @_;
	if (defined $value) {
		$self->{stopped} = $value;
		return;
	}
	return $self->{stopped};
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
	return unless -f $path;

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

sub validatePath {
	my ($self, $url) = @_;
	$url =~ s|^/+||;
	$url =~ s/[^\w\.\!\?\/\-]//g;
	$url =~ s/\.{2,}//g;
	return $url;
}

=item getPathTmp($url) String

Returns a path to the tmp folder.

C<$url> The relative path in the tmp folder.

The tmp folder is configured in the server configuration under C<server.tmp>.

=cut

sub getPathTmp {
	my ($self, $url) = @_;
	return $self->worker->getConfig('server.tmp').'/'.$self->validatePath($url);
}

=item getPathHome($url) String

Returns a path to the home folder of the server.

C<$url> The relative path in the home folder.

The tmp folder is configured in the server configuration under C<server.home>.

=cut

sub getPathHome {
	my ($self, $url) = @_;
	return $self->worker->getConfig('server.home').'/'.$self->validatePath($url);
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
