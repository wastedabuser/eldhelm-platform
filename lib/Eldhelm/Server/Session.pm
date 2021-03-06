package Eldhelm::Server::Session;

=pod

=head1 NAME

Eldhelm::Server::Session - A persistant object representing a session.

=head1 SYNOPSIS

	Eldhelm::Server::Session->new(
		myProperty => 'value'
	);

=head1 METHODS

=over

=cut

use strict;
use Carp;
use Data::Dumper;

use parent 'Eldhelm::Basic::Persist';

my @conProps = qw(fno eventFno);

=item new(%args)

Constructs a new object.

C<%args> Hash - Contructor argumets;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(
		persistType => __PACKAGE__,
		%args,
		executeMessageId => 1,
	);
	bless $self, $class;

	$self->bind("disconnect", "onDisconnect");
	$self->set("timeout", $self->worker->getConfig("server.session.".($args{http} ? "httpTimeout" : "timeout")));

	$self->setConnection($args{connection}) if $args{connection};

	return $self;
}

sub onDisconnect {
	my ($self, $args, $options) = @_;
	$self->set("connected", 0);
	return;
}

# ================================================
# connection methods
# ================================================

=item setConnection($connection) self

Connects the session with a client connection.

C<$connection> L<Eldhelm::Server::Connection> - The server connection to bond the session to.

=cut

sub setConnection {
	my ($self, $conn) = @_;

	my $wasConnected = $self->connected;
	my $currentFno   = $self->get("fno");
	$self->trigger("disconnect", { reason => "reconnect", initiator => "application" })
		if $currentFno && $wasConnected;

	my $id = $self->id;
	if ($currentFno) {
		$self->unregisterLookupProperty($_, $currentFno) foreach @conProps;
	}

	$conn->setSessionId($self->id);
	my $fno = $conn->fno;
	$self->setHash(
		eventFno  => $fno,
		fno       => $fno,
		connected => $conn->connected,
		composer  => $conn->get("composer"),
	);
	$self->registerLookupProperty($_) foreach @conProps;

	$self->sendSessionId($conn);
	$self->resendNotAcknowledged($conn);
	$self->trigger("connect", { reconnect => !$wasConnected && $currentFno });

	return $self;
}

=item getConnection() Eldhelm::Server::Connection

Returns the connection the session is bond to.

=cut

sub getConnection {
	my ($self) = @_;
	my $fno = $self->get("fno");
	return $self->worker->getConnection($fno) if $fno;

	$self->worker->error("Connection($fno) for session ".$self->id." is not available");
	return;
}

=item connected() 1 or 0 or undef

Indicates whether the session's connection is connected. 

=cut

sub connected {
	my ($self) = @_;
	return $self->get("connected");
}

=item say($data, $headers)

Sends a message along the connection. The message encoding depends on the message protocol associated with the connection.

C<$data> HashRef - The data to be sent.
C<$headers> HashRef - Headers to be sent.

=cut

sub say {
	my ($self, $data, $headers) = @_;

	my %options;
	%options = %$headers if $headers;
	my $id = $options{id} = $self->inc("sendMessageId");
	my $stream = $self->compose($data, \%options);
	$self->set("sendMessagesCache.$id", $stream);

	my $conn = $self->getConnection;
	$conn->sendStream($stream) if $conn;

	return;
}

sub sendSessionId {
	my ($self, $conn) = @_;
	$conn ||= $self->getConnection;

	my $id = $self->id;
	$self->worker->log("Sending signIn: [sessionId:$id]");

	$conn->sendData(
		{   sessionId   => $id,
			countryCode => $self->get("countryCode"),
			$self->getHashrefHash("sessionParams")
		},
		{ type => "signIn" }
	);
	$self->remove("sessionParams");

	return;
}

sub sendSignOut {
	my ($self, $conn) = @_;
	$conn ||= $self->getConnection;

	$self->worker->log("Sending signOut");
	$conn->sendSignOut({ reason => 'logout' }) if $conn;

	return;
}

sub resendNotAcknowledged {
	my ($self, $conn) = @_;
	$conn ||= $self->getConnection;

	my @list = $self->getHashrefValues("sendMessagesCache");
	$self->worker->log("Resend not acknowledged: ".@list);
	$conn->sendStream($_) foreach @list;

	return;
}

sub resetSession {
	my ($self) = @_;
	
	my $currentFno = $self->get("fno");
	if ($currentFno) {
		$self->unregisterLookupProperty($_, $currentFno) foreach @conProps;
	}
	
	my $conn = $self->getConnection;
	$conn->removeSession if $conn;
	
	$self->removeList("fno", "eventFno", "connected", "recvMaxMessageId", "recvNextMessageId");
	$self->setHash(
		executeMessageId  => 1,
		sendMessageId     => 0,
		sendMessagesCache => {}
	);
	
	$self->trigger("reset", {});
}

# ================================================
# closing the session
# ================================================


=item closed()

Indicates whether the connection was closed

=cut

sub closed {
	my ($self) = @_;
	return $self->get("closed");
}


=item close()

Closes the connection

=cut

sub close {
	my ($self) = @_;
	$self->set("closed", 1);
	$self->remove("connected");
	my $conn = $self->getConnection;
	$conn->sendSignOut({ reason => $self->get("closeSessionReason") }) if $conn;
	return;
}


=item disposeWithReason($reason)

Same as C<dispose> but sends a reason message to the client.

C<$reason> String - A word to indicate the reason for connection closing.

=cut

sub disposeWithReason {
	my ($self, $reason) = @_;
	$self->set("closeSessionReason", $reason) if $reason;
	$self->dispose;
}

# ================================================
# util and cleanup
# ================================================

sub beforeSaveState {
	my ($self) = @_;

	my $currentFno = $self->get("fno");
	if ($currentFno) {
		$self->unregisterLookupProperty($_, $currentFno) foreach @conProps;
	}

	$self->removeList(qw(fno eventFno connected));

	$self->SUPER::beforeSaveState;
}

sub dispose {
	my ($self) = @_;
	$self->close;
	$self->SUPER::dispose;
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
