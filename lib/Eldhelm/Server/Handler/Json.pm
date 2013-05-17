package Eldhelm::Server::Handler::Json;

use strict;
use Eldhelm::Server::Parser::Json;
use Eldhelm::Util::Tool;
use Data::Dumper;
use Carp;

use constant COMPOSER_NAME => "Eldhelm::Server::Parser::Json";

use base qw(Eldhelm::Server::Handler);

# static methods

sub check {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	return $data =~ m/^\["eldhlem-json-\d+\.\d+\"/ ? 1 : undef;
}

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data, $main) = @_;
	my $composer = COMPOSER_NAME;
	my ($more, %parsed) = ("");

	$data =~ s/^(\[.+?\])//;
	eval { ($parsed{protocolId}, $parsed{headers}) = @{ $composer->parse($1) }; };
	if ($@) {
		$main->error("Error parsing header: $@\n$data");
		return ({ len => -2 }, $data);
	}

	($parsed{protocolVersion}) = $parsed{protocolId} =~ /(\d+\.\d+)/;
	my $ln = int $parsed{headers}{contentLength};
	{
		use bytes;
		my $dln = length $data;
		if ($ln == 0) {
			$parsed{len} = 0;
			$more = $data;
		} elsif ($ln < $dln) {
			$parsed{content} = substr $data, 0, $ln;
			$more            = substr $data, $ln;
			$parsed{len}     = -1;
		} else {
			$parsed{content} = $data;
			$parsed{len}     = $ln - $dln;
		}
	}

	return (\%parsed, $more);
}

# the class definition

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Handler->new(%args);
	$self->{composer} = COMPOSER_NAME;
	bless $self, $class;

	return $self;
}

sub parseContent {
	my ($self, $data) = @_;
	my $headers = $self->{headers};

	if ($data) {
		eval { $self->{json} = $self->{composer}->parse($data); };
		if ($@) {
			$self->worker->error(Dumper $self->{headers});
			$self->worker->error("Error parsing json: $@\n$data");
		}
	}

	if ($self->{protocolVersion} > 1) {
		if ($headers->{type}) {
			my $fn = "$headers->{type}Command";
			eval { $self->$fn(); };
			$self->worker->error("Error processing message: $@\n$headers") if $@;
			return;
		}
		if ($headers->{id} > 0) {
			$self->acceptMessage;
			return;
		}
	}

	$self->router->route($self->{headers}, $self->{json});
}

sub acceptMessage {
	my ($self)  = @_;
	my $conn    = $self->getConnection;
	my $session = $conn->getSession;
	my ($headers, $data) = ($self->{headers}, $self->{json});
	return $self->route([ $headers, $data ]) unless $session;

	my $msgId             = int $headers->{id};
	my $recvNextMessageId = int $session->get("recvNextMessageId");

	$session->set("recvNextMessageId", $recvNextMessageId = $msgId) unless $recvNextMessageId;

	my @list;
	my $recvMaxMessageId = int $session->get("recvMaxMessageId");

	$session->set("recvMaxMessageId", $recvMaxMessageId = $msgId)
		if $msgId > $recvMaxMessageId;

	if ($msgId == $recvNextMessageId) {
		$conn->sendHeader({ type => "ack", id => $msgId });
		$recvNextMessageId = $session->inc("recvNextMessageId");
		push @list, [ $headers, $data ];

	} elsif ($msgId > $recvNextMessageId) {
		$conn->sendHeader({ type => "ack", id => $msgId });
		$conn->sendHeader({ type => "resend", from => $recvNextMessageId, to => $msgId - 1 });
		$session->set("recvMessagesCache.$msgId", [ $headers, $data ]);

	} else {
		return $self->route(@list);
	}

	if ($session->get("recvMessagesCache")) {
		foreach ($recvNextMessageId .. $recvMaxMessageId) {
			return $self->route(@list) unless $session->get("recvMessagesCache.$_");
		}
		foreach ($recvNextMessageId .. $recvMaxMessageId) {
			push @list, $session->get("recvMessagesCache.$_");
		}
		$session->remove("recvMessagesCache");
		$session->set("recvNextMessageId", $recvMaxMessageId += 1);
	}

	return $self->route(@list);
}

sub route {
	my ($self, @list) = @_;
	my $session = $self->getConnection->getSession;
	my $router  = $self->router;

	foreach (@list) {
		my ($headers, $data) = @$_;
		if ($session) {
			my $id = $headers->{id};
			if ($id && $session->get("executedMessages.$id")) {
				next;
			} else {
				$session->set("executedMessages.$id", 1);
			}
		}
		$router->route($headers, $data);
	}

	return;
}

sub ackCommand {
	my ($self) = @_;
	my $id = $self->{headers}{id};
	$self->worker->log("Request ack: $id");

	my $session = $self->getConnection->getSession;
	return unless $session;

	$session->remove("sendMessagesCache.$id");
	return;
}

sub resendCommand {
	my ($self) = @_;
	my $conn = $self->getConnection;

	my $headers = $self->{headers};
	my ($fm, $to) = ($headers->{from}, $headers->{to});
	$self->worker->log("Request resend: $fm - $to");

	my $session = $conn->getSession;
	return unless $session;

	$conn->sendStream($_) foreach $session->getHashrefValues("sendMessagesCache", [ $fm ... $to ]);

	return;
}

sub deviceInfoCommand {
	my ($self) = @_;
	my $conn = $self->getConnection;

	$self->worker->log("Request deviceInfo");
	$conn->sendData(Eldhelm::Util::Tool::merge({}, $self->executeHandler("deviceInfo", $conn),),
		{ type => "serverInfo" });

	return;
}

sub renewSessionCommand {
	my ($self) = @_;
	my $conn = $self->getConnection;
	my ($headers, $data) = ($self->{headers}, $self->{json});
	my $id = $data->{sessionId};

	$self->worker->log("Request renewSession: $id");
	my $session = $self->worker->getPersist($id);

	if ($session && !$session->closed) {
		$session->setConnection($conn);
	} else {
		$conn->sendSignOut;
	}

	return;
}

sub compose {
	my ($self, $data) = @_;
	return $self->{reader}->write($data);
}

sub createUnauthorizedResponse {
	my ($self, $controller) = @_;
	return unless $controller->rpcId;

	my $debug = $controller->callDebug;
	$controller->rpcRespond(undef, 0, ["server_error_unauthorized_request"], $debug);
}

sub createErrorResponse {
	my ($self, $controller) = @_;
	return unless $controller->rpcId;

	$controller->rpcRespond(undef, 0, ["server_error"]);
}

sub finish {
	my ($self) = @_;
	$self->worker->endTask if $self->{json} && $self->{json}{rpc};
}

sub executeHandler {
	my ($self, $name, $conn) = @_;

	my $handlers = $self->worker->getConfig("server.json.handlers.$name");
	return () if ref $handlers ne "ARRAY";

	my $router = $self->router;
	my @results;
	foreach (@$handlers) {
		my ($h, $c, $r) = $router->doAction($_, $self->{json});
		push @results, @$r;
	}

	return @results;
}

1;
