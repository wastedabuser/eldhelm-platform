package Eldhelm::Server::Handler::RoutingHandler;

use strict;
use Eldhelm::Server::Parser::Json;
use Eldhelm::Util::Tool;
use Data::Dumper;
use Carp;

use base qw(Eldhelm::Server::Handler);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	return $self;
}

sub parseContent {
	my ($self, $data) = @_;
	my $headers = $self->{headers};

	if ($data) {
		eval {
			$self->{json} = $self->{composer}->parse($data);
			1;
		} or do {
			$self->worker->error(Dumper $self->{headers});
			$self->worker->error("Error parsing json: $@\n$data");
		};
	}

	if ($self->{protocolVersion} > 1) {
		if ($headers->{type}) {
			my $fn = "$headers->{type}Command";
			$self->worker->status('task', $fn);
			eval {
				$self->$fn();
				1;
			} or do {
				$self->worker->error("Error processing message: $@\n$headers");
			};
			return;
		}
		if ($headers->{id} > 0) {
			$self->worker->status('task', $data);
			$self->acceptMessage;
			return;
		}
	}

	$self->worker->status('task', $data);
	$self->router->route($self->{headers}, $self->{json});
}

sub acceptMessage {
	my ($self)  = @_;
	my $conn    = $self->getConnection;
	my $session = $conn->getSession;
	my ($headers, $data) = ($self->{headers}, $self->{json});

	my $msgId = int $headers->{id};
	unless ($session) {
		$conn->sendHeader({ type => 'ack', id => $msgId });
		return $self->route([ $headers, $data ]);
	}

	my $recvNextMessageId = int $session->get('recvNextMessageId');
	$session->set('recvNextMessageId', $recvNextMessageId = $msgId) unless $recvNextMessageId;

	my @list;
	my $recvMaxMessageId = int $session->get('recvMaxMessageId');

	$session->set('recvMaxMessageId', $recvMaxMessageId = $msgId)
		if $msgId > $recvMaxMessageId;

	if ($msgId == $recvNextMessageId) {
		$conn->sendHeader({ type => 'ack', id => $msgId });
		$recvNextMessageId = $session->inc('recvNextMessageId');
		push @list, [ $headers, $data ];

	} elsif ($msgId > $recvNextMessageId) {
		$conn->sendHeader({ type => 'ack', id => $msgId });
		$conn->sendHeader({ type => 'resend', from => $recvNextMessageId, to => $msgId - 1 });
		$session->set("recvMessagesCache.$msgId", [ $headers, $data ]);

	} else {
		return $self->route(@list);
	}

	if ($session->get('recvMessagesCache')) {
		foreach ($recvNextMessageId .. $recvMaxMessageId) {
			return $self->route(@list) unless $session->get("recvMessagesCache.$_");
		}
		foreach ($recvNextMessageId .. $recvMaxMessageId) {
			push @list, $session->get("recvMessagesCache.$_");
		}
		$session->remove('recvMessagesCache');
		$session->set('recvNextMessageId', $recvMaxMessageId += 1);
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
			if ($id) {
				my $eid = $session->get('executeMessageId');
				next if $id < $eid;

				$session->inc('executeMessageId');
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

	$conn->sendStream($_) foreach $session->getHashrefValues('sendMessagesCache', [ $fm ... $to ]);

	return;
}

sub deviceInfoCommand {
	my ($self) = @_;
	my $conn = $self->getConnection;

	$self->worker->log('Request deviceInfo');
	$conn->sendData(Eldhelm::Util::Tool->merge({}, $self->executeHandler('deviceInfo', $conn)),
		{ type => 'serverInfo' });

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
	$controller->rpcRespond(undef, 0, ['server_error_unauthorized_request'], $debug);
}

sub createErrorResponse {
	my ($self, $controller, $message) = @_;
	return unless $controller->rpcId;

	$controller->rpcRespond(undef, 0, ['server_error'], { message => $message });
}

sub finish {
	my ($self) = @_;
	$self->worker->endTask if $self->{json} && $self->{json}{rpc};
}

sub executeHandler {
	my ($self, $name, $conn) = @_;

	my $handlers = $self->worker->getConfig("server.json.handlers.$name");
	return () if ref $handlers ne 'ARRAY';

	my $router = $self->router;
	my @results;
	foreach (@$handlers) {
		my ($h, $c, $r) = $router->doAction($_, $self->{json});
		push @results, @$r;
	}

	return @results;
}

1;
