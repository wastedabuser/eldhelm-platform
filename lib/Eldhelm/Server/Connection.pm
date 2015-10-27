package Eldhelm::Server::Connection;

=pod

=head1 NAME

Eldhelm::Server::Connection - An object representing a server connection.

=head1 SYNOPSIS

Connection classes are created by the server you should be able to get them like this:

	Eldhelm::Basic::Controller->connection;
	
See L<Eldhelm::Basic::Controller> for more details.

=head1 METHODS

=over

=cut

use strict;
use Carp;
use Eldhelm::Util::Factory;
use Data::Dumper;

use base qw(Eldhelm::Server::BaseObject);

=item fno() Number

Returns a file handle number represnting the current connection.

=cut

sub fno {
	my ($self) = @_;
	return $self->get("fno");
}

=item host() String

Returns the client host(ip).

=cut

sub host {
	my ($self) = @_;
	return $self->get("peerhost");
}

=item port() String

Returns the client port.

=cut

sub port {
	my ($self) = @_;
	return $self->get("peerport");
}

=item connected() 1 or 0

Returns the connection status.

=cut

sub connected {
	my ($self) = @_;
	return $self->get("connected");
}

=item close()

Closes the connection

=cut

sub close {
	my ($self, $event) = @_;
	return $self->worker->closeConnection($self->fno, $event);
}

# ==============================================
# session related
# ==============================================

sub setSessionId {
	my ($self, $id) = @_;
	$self->set("sessionId", $id);
	return $self;
}

=item getSessionId() String

Returns the id of the associated session.

=cut

sub getSessionId {
	my ($self) = @_;
	return $self->get("sessionId") || $self->worker->getPersistId("fno", $self->fno);
}

sub removeSession {
	my ($self) = @_;
	$self->remove("sessionId");
	return $self;
}

=item hasSession() 1 or undef

Returns whether the connection has session or if it does whether it is still alive.

=cut

sub hasSession {
	my ($self) = @_;
	return $self->worker->hasPersist($self->getSessionId);
}

=item getSession() Eldhelm::Server::Session

Returns the L<Eldhelm::Server::Session> object associated with this connection.

=cut

sub getSession {
	my ($self) = @_;
	my $session = $self->worker->getPersist($self->getSessionId);

	return $session;
}

sub sendData {
	my ($self, $data, $headers) = @_;
	my $stream = $self->compose($data, $headers);
	$self->worker->sendData($stream, $self->fno);
	return $stream;
}

sub sendStream {
	my ($self, $stream) = @_;
	return $self->worker->sendData($stream, $self->fno);
}

sub sendHeader {
	my ($self, $data) = @_;
	return $self->sendData(undef, $data);
}

=item say($data, $headers) self

Sends a message along the connection. The message encoding depends on the message protocol associated with this connection.

C<$data> HashRef - The data to be sent.
C<$headers> HashRef - Headers to be sent.

=cut

sub say {
	my ($self, $data, $headers) = @_;
	my $session = $self->getSession;
	if ($session) {
		my %options;
		%options = %$headers if $headers;
		my $id = $options{id} = $session->inc("sendMessageId");
		$session->set("sendMessagesCache.$id", $self->sendData($data, \%options));
	} else {
		$self->sendData($data, $headers);
	}
	return $self;
}

sub sendSignOut {
	my ($self, $data) = @_;
	$self->sendData($data, { type => "signOut" });
	return;
}

sub sendDeny {
	my ($self, $data) = @_;
	$self->sendData($data, { type => "deny" });
	return;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
