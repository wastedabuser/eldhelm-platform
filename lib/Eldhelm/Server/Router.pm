package Eldhelm::Server::Router;

use strict;
use Eldhelm::Util::Factory;
use Eldhelm::Util::Tool;
use Eldhelm::Basic::Controller;
use Carp;
use Carp qw(longmess);
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = {
		connection => $args{connection},
		config     => $args{config} || {},
		errors     => [],
	};
	bless $self, $class;

	return $self;
}

sub worker {
	Eldhelm::Server::Child->instance;
}

sub handler {
	my ($self) = @_;
	return $self->worker->{handler};
}

sub config {
	my ($self, $conf) = @_;
	Eldhelm::Util::Tool->merge($self, $conf);
	return $self;
}

sub actions {
	my ($self) = @_;
	return $self->{config}{actions} || $self->worker->getConfig('server.router.actions') || [];
}

sub defaultMethod {
	my ($self) = @_;
	return $self->{config}{defaultMethod} || $self->worker->getConfig('server.router.defaultMethod') || 'index';
}

sub route {
	my ($self, $headers, $data) = @_;

	return if ref $data ne 'HASH';
	$self->{requestHeaders} = $headers;

	($data->{type}, $data->{command}) = $self->parseControllerName($data->{rpc})
		if $data->{rpc};
	$data->{action} ||= "$data->{type}:$data->{command}";

	$self->{connection}->setSessionId($data->{sessionId})
		if $data->{sessionId};

	return $self->doAction($data->{action}, $data->{data} || $data->{params});
}

sub parseControllerName {
	my ($self, $name) = @_;
	return $self->parseAction($name) if $name =~ /:/;
	my @list = split /\./, $name;
	my $method = pop @list;
	return join('.', @list), $method;
}

sub doAction {
	my ($self, $action, $data, $private) = @_;

	my $conn = $self->{connection};
	my ($class, $method) = $self->parseAction($action);
	$method ||= $self->defaultMethod;
	my $controller = $self->getInstance(
		$class,
		connection     => $conn,
		data           => $data,
		requestHeaders => $self->{requestHeaders},
	);
	return ([],
		[ $self->handler->createErrorResponse($controller, "Can't call action $action on Eldhelm::Basic::Controller") ])
		if ref $controller eq 'Eldhelm::Basic::Controller';

	unless ($private || $controller->canCall($method)) {
		$self->addError("Can not call action '$action'", $controller->callDump($method));
		return ([], [ $self->handler->createUnauthorizedResponse($controller) ]);
	}

	my $moreActions = $self->getRelatedActions(
		$action,
		connection => $conn,
		data       => $data,
	);

	my @list = (
		@{ $moreActions->{before}{all} || [] },
		@{ $moreActions->{before}{$method} || [] },
		[ $controller, $method ],
		@{ $moreActions->{after}{$method} || [] },
		@{ $moreActions->{after}{all} || [] },
	);

	my (@results, @headers, @contents);
	eval {
		foreach my $ex (@list) {
			my $c = $ex->[0];
			push @results,  $self->executeControllerMethod(@$ex);
			push @headers,  $c->getResponseHeaders;
			push @contents, $c->getResponseContent;
			last if $c->{ended};
		}
		1;
	} or do {
		$self->addError("Error while calling '$method'", Dumper($data)."\n".$self->smartTrace($@));
		return ([], [ $self->handler->createErrorResponse($controller, $@) ]);
	};

	return (\@headers, \@contents, \@results);
}

sub parseAction {
	my ($self, $action) = @_;
	return split /:/, $action;
}

sub getRelatedActions {
	my ($self, $action, %args) = @_;
	my %actions;
	foreach my $a (@{ $self->actions }) {
		next if $action !~ /$a->[0]/;
		my ($type, $methods) = split /:/, $a->[1];
		my ($class, $method) = $self->parseAction($a->[2]);
		push @{ $actions{$type}{$_} }, [ $self->getInstance($class, %args), $method ] foreach split /,/, $methods;
	}
	return \%actions;
}

sub executeControllerMethod {
	my ($self, $controller, $method, @args) = @_;
	$self->worker->log("Calling '$controller' '$method'", 'access');
	return $controller->call($method, @args);
}

sub executeAction {
	my ($self,  $name,   @args)   = @_;
	my ($class, $method, $result) = $self->parseControllerName($name);
	my $controller = $self->getInstance($class);
	return ([],
		[ $self->handler->createErrorResponse($controller, "Can't call method $method on Eldhelm::Basic::Controller") ])
		if ref $controller eq 'Eldhelm::Basic::Controller';

	eval {
		$result = $self->executeControllerMethod($controller, $method, @args);
		1;
	} or do {
		$self->worker->error("Error while calling '$name': ".Dumper(\@args).': '.$self->smartTrace($@));
		return ($controller, $self->handler->createErrorResponse($controller, $@));
	};

	return ($controller, $result);
}

sub getInstance {
	my ($self, $class, %args) = @_;
	my $inst;
	eval {
		$inst = Eldhelm::Util::Factory->instanceFromNotation(
			'Eldhelm::Application::Controller',
			$class, %args,
			router => $self,
			worker => $self->worker,
		);
		1;
	} or do {
		$self->addError("Can not create controller '$class'", $@);
		$inst = Eldhelm::Basic::Controller->new(
			%args,
			router => $self,
			worker => $self->worker,
		);
	};
	return $inst;
}

sub addError {
	my ($self, $msg, $stackTrace) = @_;
	$self->worker->error("$msg: $stackTrace");
	push @{ $self->{errors} }, [ $msg, $stackTrace ];
}

sub getErrors {
	my ($self) = @_;
	return @{ $self->{errors} };
}

sub hasErrors {
	my ($self) = @_;
	return scalar @{ $self->{errors} };
}

sub clearErrors {
	my ($self) = @_;
	$self->{errors} = [];
	return $self;
}

sub smartTrace {
	my ($self, $error) = @_;
	return $error =~ /called at .*? line \d+/ ? $error : longmess($error);
}

1;
