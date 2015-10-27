package Eldhelm::Basic::Controller;

=pod

=head1 NAME

Eldhelm::Basic::Controller - The base for all controller classes.

=head1 SYNOPSIS

This class should be inherited in order to be used. Like this:

	package Eldhelm::Application::Controller::MyController;
	
	use strict;
	use base 'Eldhelm::Basic::Controller';
	
	sub new {
		my ($class, %args) = @_;
		my $self = $class->SUPER::new(%args);
		bless $self, $class;
	
		my @list = qw(hello);
		
		# this will make the method accessible
		$self->export(@list);
		
		# and this will make it accessible without a session 
		$self->public(@list);
		
		# hook something before and/or after the method
		$self->before('myAction', 'beforeMyAction');
		$self->after('myAction', 'afterMyAction');
		
		return $self;
	}
	
	sub myAction {
		my ($self) = @_;
		
		# getting the coonection and 
		# the request params is very common
		# do it like this
		my ($conn, $data) = ($self->connection, $self->data);
		
	}
	
	sub beforeMyAction {
		my ($self) = @_;
		
		# do something here ...
	}
	
	sub afterMyAction {
		my ($self) = @_;
		
		# do something here ...
	}
	
	1;

=head1 DESCRIPTION

When you ihnerit this calls and add your own methods, you do add the so called actions.
Actions are handlers for remote calls and server events.

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Basic::View;
use Eldhelm::Database::Pool;
use Eldhelm::Util::Tool;
use Eldhelm::Server::Parser::Json;
use Eldhelm::Basic::Script;
use Data::Dumper;
use Carp;

=item new(%args)

Constructs a new object.

C<%args> Hash - Contructor argumets;

C<worker> Eldhelm::Server::Worker - the worker context of the current controller;
C<connection> Eldhelm::Server::Connection - a connection caused the execution;
C<data> HashRef - data from the current request;
C<requestHeaders> HashRef - headers sent by the current request, available only if the protocol supports such thing;

=cut

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
		cachedModels   => $args{cachedModels} || {},
		views          => [],
		content        => "",
		headers        => [],
	};
	bless $self, $class;

	return $self;
}

sub call {
	my ($self, $method, @args) = @_;
	$self->callActions('before', 'all',   @args);
	$self->callActions('before', $method, @args);
	my $result = $self->$method(@args);
	$self->callActions('after', $method, @args);
	$self->callActions('after', 'all',   @args);
	return $result;
}

sub callActions {
	my ($self, $type, $method, @args) = @_;
	my $ref = $self->{"${type}Actions"}{$method};
	return if !$ref;
	foreach (@$ref) {
		if (ref $_ eq 'CODE') {
			$_->($self, @args);
		} else {
			$self->$_(@args);
		}
	}
	return $self;
}

=item before($names, $method)

Creates a hook before a method is executed.

=cut

sub before {
	my ($self, $names, $method) = @_;
	return $self->action('before', $names, $method);
}

=item after($names, $method)

Creates a hook after a method is executed.

=cut

sub after {
	my ($self, $names, $method) = @_;
	return $self->action('after', $names, $method);
}

sub action {
	my ($self, $type, $names, $method) = @_;
	push @{ $self->{"${type}Actions"}{$_} }, $method foreach Eldhelm::Util::Tool->toList($names);
	return $self;

}

=item export(@list) self

Marks a method to be available for remote calling.

=cut

sub export {
	my $self = shift;
	$self->{exported}{$_} = 1 foreach @_;
	return $self;
}

=item public(@list) self

Marks methods to be publicly accessible. This means that the connection that triggered the current execution is not necessary bound to a L<Eldhelm::Server::Session>.

=cut

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

=item worker() Eldhelm::Server::Worker

Returns the current worker thread wrapper class.

=cut

sub worker {
	my ($self) = @_;
	return $self->{worker};
}

=item connection() Eldhelm::Server::Connection

Returns the connection which triggered the current execution.

=cut

sub connection {
	my ($self) = @_;
	return $self->{connection};
}

sub getConnection {
	my ($self) = @_;
	return $self->{connection};
}

=item handler() Eldhelm::Server::Handler

Return the current handler. This is the class handling the current protocol. 
This is a class in the Eldhelm::Server::Handler namespace.

=cut

sub handler {
	my ($self) = @_;
	return $self->{worker}{handler};
}

sub getHandler {
	my ($self) = @_;
	return $self->{worker}{handler};
}

=item data() HashRef

The incomming data of the current context. These are the controller method arguments.

=cut

sub data {
	my ($self) = @_;
	return $self->{data};
}

sub canCall {
	my ($self, $fn) = @_;

	return unless $self->{exported}{$fn};
	return 1 if $self->{public}{$fn};

	return unless $self->{connection};

	my $sess = $self->{connection}->getSession;
	return unless $sess;

	my $isCon = $sess->connected;
	return if defined $isCon && !$isCon;

	return 1;
}

sub callDump {
	my ($self, $fn) = @_;
	return Dumper($self->callDebug($fn));
}

sub callDebug {
	my ($self, $fn) = @_;
	my $conn = $self->{connection};
	my %more;
	if ($conn) {
		$more{connection} = $conn->fno;
		my $sess = $conn->getSession;
		if ($sess) {
			%more = (
				%more,
				sessionConnected => $sess->connected,
				sessionClosed    => $sess->closed,
				sessionId        => $sess->id,
			);
			my $conn = $sess->getConnection;
			$more{sessionConnection} = $conn->fno if $conn;
		}
	}
	return {
		exported => $self->{exported}{$fn},
		public   => $self->{public}{$fn},
		%more,
	};
}

=item getController($name) Eldhelm::Basic::Controller

Creates a controller object for direct manipulation.

C<$name> String - a dotted notation poiting to a class in the C<Eldhelm::Application::Controller> namespace;

=cut

sub getController {
	my ($self, $name) = @_;
	return $self->{router}->getInstance($name, data => $self->{data}, connection => $self->{connection});
}

sub routeAction {
	my ($self, $action, $data) = @_;
	return $self->{router}->doAction($action, $data, 1);
}

=item responseWrite($data) self

Writes $data to the output. Works only if the current protocol/handler support such thing.

C<$data> String;

=cut

sub responseWrite {
	my ($self, $data) = @_;
	$self->{content} .= $data;
	return $self;
}

=item responseWriteJson($data) self

Writes json ecoded $data to the output. Works only if the current protocol/handler support such thing.

C<$data> Array or Hashref;

=cut

sub responseWriteJson {
	my ($self, $data) = @_;
	$self->{content} .= Eldhelm::Server::Parser::Json->encodeFixNumbers($data);
	return $self;
}

=item addHeader($name, $value) self

Adds a header to the response. Works only if the current protocol/handler support such thing.

C<$name> String - the name of the header;
C<$value> String - the value of the header;

=cut

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

=item getView($view, $args, $standAlone) Eldhelm::Application::View

Returns a view object by name.

C<$view> String - a dotted notation poiting to a class in the C<Eldhelm::Application::View> namespace;
C<$args> HashRef - arguments passed to the view constructor;
C<$standAlone> 1 or undef - whteher to bind the view to the controller lifecycle, defaults to undef;

=cut

sub getView {
	my ($self, $view, $args, $standAlone) = @_;
	$args ||= {};
	my $inst;
	if (ref $view eq 'HASH') {
		$inst = Eldhelm::Basic::View->new(%$view, data => $self->{data});
	} elsif ($view) {
		$inst =
			Eldhelm::Util::Factory->instanceFromNotation('Eldhelm::Application::View', $view, %$args,
			data => $self->{data});
	} else {
		$inst = Eldhelm::Basic::View->new(%$args, data => $self->{data});
	}
	push @{ $self->{views} }, $inst if !$standAlone;
	return $inst;
}

=item getModel($model, $args) Eldhelm::Application::Model

Returns a model object by name.

C<$model> String - a dotted notation poiting to a class in the C<Eldhelm::Application::Model> namespace;
C<$args> HashRef - arguments passed to the model constructor;

=cut

sub getModel {
	my ($self, $model, $args) = @_;
	return $self->{cachedModels}{$model} if $self->{cachedModels}{$model};

	$args ||= {};
	return Eldhelm::Util::Factory->instanceFromNotation('Eldhelm::Application::Model', $model, %$args);
}

=item getScript($script) Eldhelm::Basic::Script

Creates a script context object for executing external script files.

C<$script> String - a dotted notation poiting to file in the C<Eldhelm::Application::Template> namespace;

=cut

sub getScript {
	my ($self, $script) = @_;
	return Eldhelm::Basic::Script->new(file => $script);
}

=item log($message, $logName) self

Logs a string $message into the log specified. Where $LogName might be error, general, debug, etc.

=cut

sub log {
	my ($self, $msg, $type) = @_;
	$self->{worker}->log($msg, $type);
	return $self;
}

=item rpcRespond($data, $success, $errors, $flags)

Responds to a rpc request. Does not end the execution!

C<$data> HashRef or ArrayRef - the data to be sent as a response;
C<$success> 0 or 1 - indicates the status. Defaults to 1;
C<$errors> ArrayRef - A list of strings indicating error codes or messages;
C<$flags> HashRef - Special flags used by the rpc protocol;

=cut

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
		$self->worker->error('The current request is not RPC: '.Dumper($self->{requestHeaders})."\n".Dumper($response));
		return;
	}

	$conn->say($response, { rpcId => $rpcId });
}

sub rpcId {
	my ($self, $value) = @_;
	return $self->{requestHeaders}{rpcId} = $value if $value;
	
	return $self->{requestHeaders}{rpcId};
}

=item trigger($name, $argsList) self

Triggers a named event. This will result in executing on or more methods from other controllers.
Event handlers are configured into the configuration file in server.router.events

C<$name> string - event name;
C<$argsList> ArrayRef - list of arguments;

=cut

sub trigger {
	my ($self, $name, $argsList) = @_;
	my $list = $self->worker->getConfig("server.router.events.$name");
	return $self unless $list;

	my $router = $self->{router};
	$router->executeAction($_, $argsList ? @$argsList : ()) foreach @$list;

	return $self;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
