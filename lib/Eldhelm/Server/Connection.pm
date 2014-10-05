package Eldhelm::Server::Connection;

use strict;
use Carp;
use Eldhelm::Util::Factory;
use Data::Dumper;

use base qw(Eldhelm::Server::BaseObject);

sub fno {
	my ($self) = @_;
	return $self->get("fno");
}

sub host {
	my ($self) = @_;
	return $self->get("peerhost");
}

sub port {
	my ($self) = @_;
	return $self->get("peerport");
}

sub connected {
	my ($self) = @_;
	return $self->get("connected");
}

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

sub getSessionId {
	my ($self) = @_;
	return $self->get("sessionId") || $self->worker->getPersistId("fno", $self->fno);
}

sub removeSession {
	my ($self) = @_;
	$self->remove("sessionId");
	return $self;
}

sub hasSession {
	my ($self) = @_;
	return $self->worker->hasPersist($self->getSessionId);
}

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

1;
