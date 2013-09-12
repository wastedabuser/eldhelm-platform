package Eldhelm::Basic::Controller;

use strict;
use Eldhelm::Basic::View;
use Eldhelm::Database::Pool;
use Eldhelm::Util::Tool;
use Eldhelm::Server::Parser::Json;
use Data::Dumper;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {
		worker         => $args{worker},
		dbPool         => Eldhelm::Database::Pool->new,
		router         => $args{router},
		connection     => $args{connection},
		data           => $args{data},
		requestHeaders => $args{requestHeaders} || {},
		exported       => {},
		public         => {},
		views          => [],
		content        => "",
		headers        => [],
	};
	bless $self, $class;

	return $self;
}

sub call {
	my ($self, $method, @args) = @_;
	$self->callActions("before", "all",   @args);
	$self->callActions("before", $method, @args);
	my $result = $self->$method(@args);
	$self->callActions("after", $method, @args);
	$self->callActions("after", "all",   @args);
	return $result;
}

sub callActions {
	my ($self, $type, $method, @args) = @_;
	my $ref = $self->{"${type}Actions"}{$method};
	return if !$ref;
	foreach (@$ref) {
		if (ref $_ eq "CODE") {
			$_->($self, @args);
		} else {
			$self->$_(@args);
		}
	}
	return $self;
}

sub before {
	my ($self, $names, $method) = @_;
	return $self->action("before", $names, $method);
}

sub after {
	my ($self, $names, $method) = @_;
	return $self->action("after", $names, $method);
}

sub action {
	my ($self, $type, $names, $method) = @_;
	push @{ $self->{"${type}Actions"}{$_} }, $method foreach Eldhelm::Util::Tool->toList($names);
	return $self;

}

sub export {
	my $self = shift;
	$self->{exported}{$_} = 1 foreach @_;
	return $self;
}

sub public {
	my $self = shift;
	$self->{public}{$_} = 1 foreach @_;
	return $self;
}

sub end {
	my ($self) = @_;
	$self->{ended} = 1;
	return $self;
}

sub endWithStatus {
	my ($self, $code, @args) = @_;
	$self->{content} = $self->getHandler->createStatusResponse($code, @args);
	return $self->end;
}

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

sub canCall {
	my ($self, $fn) = @_;

	return unless $self->{exported}{$fn};
	return 1 if $self->{public}{$fn};

	my $sess = $self->{connection}->getSession;
	return unless $sess;

	my $isCon = $sess->connected;
	return if defined $isCon && !$isCon;

	return 1;
}

sub callDump {
	my ($self, $fn) = @_;
	return Dumper($self->callDebug);
}

sub callDebug {
	my ($self, $fn) = @_;
	my $sess = $self->{connection}->getSession;
	my %more;
	if ($sess) {
		%more = (
			sessionConnected => $sess->connected,
			sessionClosed    => $sess->closed,
			sessionId        => $sess->id,
		);
		my $conn = $sess->getConnection;
		$more{sessionConnection} = $conn->fno if $conn;
	}
	return {
		exported   => $self->{exported}{$fn},
		public     => $self->{public}{$fn},
		connection => $self->{connection}{fno},
		%more,

	};
}

sub getConnection {
	my ($self) = @_;
	return $self->{connection};
}

sub getController {
	my ($self, $name) = @_;
	return $self->{router}->getInstance($name, data => $self->{data}, connection => $self->{connection});
}

sub getHandler {
	my ($self) = @_;
	return $self->{worker}{handler};
}

sub responseWrite {
	my ($self, $data) = @_;
	$self->{content} .= $data;
	return $self;
}

sub responseWriteJson {
	my ($self, $data) = @_;
	$self->{content} .= Eldhelm::Server::Parser::Json->encodeFixNumbers($data);
	return $self;
}

sub addHeader {
	my ($self, $name, $value) = @_;
	push @{ $self->{headers} }, "$name: $value";
	return $self;
}

sub getResponseHeaders {
	my ($self) = @_;
	return @{ $self->{headers} };
}

sub getResponseContent {
	my ($self) = @_;
	return join "", $self->{content}, map { $_->compile } @{ $self->{views} };
}

sub getView {
	my ($self, $view, $args, $standAlone) = @_;
	$args ||= {};
	my $inst;
	if ($view) {
		$inst =
			Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Application::View", $view, %$args,
			data => $self->{data});
	} else {
		$inst = Eldhelm::Basic::View->new(%$args, data => $self->{data});
	}
	push @{ $self->{views} }, $inst if !$standAlone;
	return $inst;
}

sub getModel {
	my ($self, $model, $args) = @_;
	$args ||= {};
	return Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Application::Model", $model, %$args);
}

sub log {
	my ($self, $msg) = @_;
	$self->{worker}->log($msg);
	return $self;
}

sub rpcRespond {
	my ($self, $data, $success, $errors, $flags) = @_;
	my $conn = $self->getConnection;
	return unless $conn;

	my $response = {
		success => !defined($success) ? 1 : $success,
		data => $data,
		$errors ? (errors => $errors) : (),
		$flags  ? (flags  => $flags)  : (),
	};
	my $rpcId = $self->rpcId;

	unless ($rpcId) {
		$self->worker->error("The current request is not RPC: ".Dumper($self->{requestHeaders})."\n".Dumper($response));
		return;
	}

	$conn->say($response, { rpcId => $rpcId });
}

sub rpcId {
	my ($self) = @_;
	return $self->{requestHeaders}{rpcId};
}

1;
