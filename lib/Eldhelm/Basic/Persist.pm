package Eldhelm::Basic::Persist;

=pod

=head1 NAME

Eldhelm::Basic::Persist - The base for all persistant objects.

=head1 SYNOPSIS

In general you should inherit this class and cerate your own persistant object.
You can still use it as a general purpose object, but it is not advised.

=head1 DESCRIPTION

This class provides all the base functionality a persistant object needs.

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Server::Child;
use Eldhelm::Util::Tool;
use Digest::MD5;
use Carp;
use Data::Dumper;
use Storable;
use Time::HiRes qw(time);
use Math::Random::MT qw(rand);
use threads;
use threads::shared;

use parent 'Eldhelm::Server::BaseObject';

my $instanceIndex = 0;

=item new(%args)

Constructs a new object.

C<%args> Hash - Contructor argumets;

=cut

sub new {
	my ($class, %args) = @_;

	my $id = $args{id};
	unless ($id) {
		$id = createId();
		while ($class->worker->hasPersist($id)) {
			$id = createId();
		}
	}

	my %data = (
		%args,
		id                        => $id,
		timeout                   => $class->worker->getConfig('server.garbageCollect.persists'),
		createdon                 => time,
		updatedon                 => time,
		__events                  => shared_clone({}),
		__persistLookupProperties => shared_clone({}),
	);
	my $self = $class->worker->registerPersist(\%data);
	bless $self, $class;

	$self->register;

	return $self;
}

sub router {
	my ($self) = @_;
	return $self->worker->router;
}

=item getModel($model, $args) Eldhelm::Application::Model

Returns a model object by name.

C<$model> String - a dotted notation poiting to a class in the Eldhelm::Application::Model namespace;
C<$args> HashRef - arguments passed to the model constructor;

=cut

sub getModel {
	my ($self, $model, $args) = @_;
	$args ||= {};
	return Eldhelm::Util::Factory->instanceFromNotation('Eldhelm::Application::Model', $model, %$args);
}

sub createId {
	$instanceIndex++;
	return Digest::MD5->new->add(time.'r'.rand().'i'.$instanceIndex)->hexdigest;
}

sub register {
	my ($self) = @_;

	my @props = $self->getPureList('lookupProperties');
	$self->registerLookupProperty($_) foreach @props;

	return $self;
}

sub registerLookupProperty {
	my ($self, $name) = @_;

	my $value = $self->get($name);
	return $self if !$value;

	my $key = $self->worker->registerPersistLookup($self->id, $name, $value);
	$self->set("__persistLookupProperties.$key", 1);

	return $key;
}

sub unregisterLookupProperty {
	my ($self, @keys) = @_;

	my $key = $self->worker->unregisterPersistLookup(@keys);
	$self->remove("__persistLookupProperties.$key");

	return $key;
}

sub unregister {
	my ($self) = @_;

	$self->worker->unregisterPersistLookup($_) foreach $self->getHashrefKeys('__persistLookupProperties');
	$self->worker->unregisterPersist($self);

	return $self;
}

=item id() String

The id of the persistant object.

=cut

sub id {
	my ($self) = @_;
	return $self->get('id');
}

=item persistType() String

The ref() name of the persistant object.

=cut

sub persistType {
	my ($self) = @_;
	return $self->get('persistType');
}

sub call {
	my ($self, $fn, @data) = @_;
	return $self->$fn(@data) if $self->can($fn);
	return;
}

=item one($name, $handle, $args) String

See bind. The only difference is that this event will be executed only once.

=cut

sub one {
	my ($self, $type, $handle, $args) = @_;
	return $self->addEvent(
		$type,
		{   handle => $handle,
			one    => 1,
		},
		$args
	);
}

=item bind($name, $handle, $args) String

Binds an event to be executed. Returns an event id.

C<$name> String - the name of the event;
C<$handle> String - dotted notation to method or a controller method.
C<$args> HashRef - Arguments to be passed to the executed handler.

=cut

sub bind {
	my ($self, $type, $handle, $args) = @_;
	return $self->addEvent($type, { handle => $handle, }, $args);
}

sub addEvent {
	my ($self, $type, $options, $args) = @_;

	my $id;
	{
		lock($self);
		$id = ++$self->{__lastEventId};
	}

	my $events = $self->get('__events');
	lock($events);

	$events->{$type} = shared_clone({}) if !$events->{$type};

	$events->{$type}{$id} = shared_clone(
		{   type => $type,
			args => $args,
			%$options,
		}
	);

	return $id;
}

=item unbind($name, $id) self

Removes event listeners by name and id. If the id is ommited all events mathcing the name will be removed.

C<$name> String - the name of the event;
C<$id> String - The id returned by the bind or one methods;

=cut

sub unbind {
	my ($self, $type, $id) = @_;
	my $events = $self->get('__events');

	if ($id =~ /^\d+$/) {
		my $tpEvents;
		{
			lock($events);
			$tpEvents = $events->{$type};
		}
		return $self unless $tpEvents;
		lock($tpEvents);

		delete $tpEvents->{$id};

	} elsif ($id) {
		my $tpEvents;
		{
			lock($events);
			$tpEvents = $events->{$type};
		}
		return $self unless $tpEvents;
		lock($tpEvents);

		my @list = keys %$tpEvents;
		foreach (@list) {
			delete $tpEvents->{$_} if $tpEvents->{$_}{handle} eq $id;
		}

	} else {
		lock($events);
		delete $events->{$type};
	}
	return $self;
}

=item trigger($name, $options) self

Triggers an event.

C<$name> String - the name of the event;
C<$options> HashRef - options to be passed to the handling method;

=cut

sub trigger {
	my ($self, $type, $options) = @_;
	my $events = $self->get('__events');
	return $self unless $events;

	my $tpEvents;
	{
		lock($events);
		$tpEvents = $events->{$type};
	}
	return $self unless $tpEvents;

	my @events;
	{
		lock($tpEvents);
		my @ids = keys %$tpEvents;
		foreach my $id (@ids) {
			my $ev = $tpEvents->{$id};
			push @events, Eldhelm::Util::Tool::cloneStructure($ev);
			delete $tpEvents->{$id} if $ev->{one};
		}
	}

	$self->doEvent($_, $options) foreach @events;

	return $self;
}

sub doEvent {
	my ($self, $event, $options) = @_;
	my $handle = $event->{handle};
	if ($handle =~ /[\.:]/) {
		$self->router->executeAction($handle, $self, $event->{args}, $options);
	} else {
		$self->call($handle, $event->{args}, $options);
	}
	return $self;
}

=item delay($interval, $handle, $args) String

Registers a delayed call. Will return the id of the delay.

C<$interval> Number - seconds to wait;
C<$handle> String - A dotted notation to handler method;
C<$args> HashRef - Arguments to be passed to the handling method;

=cut

sub delay {
	my ($self, $interval, $handle, $args) = @_;
	return $self->worker->delay($interval, $handle, $args, $self->id);
}

=item cancelDelay($delayId) self

Cancels a delay by id.

C<$delayId> String - The id returned by the delay method call;

=cut

sub cancelDelay {
	my ($self, $delayId) = @_;
	$self->worker->cancelDelay($delayId);
	return $self;
}

sub beforeSaveState {
	my ($self) = @_;

}

=item dispose()

A destructor. Might be invoked manually to dispose an object.
Triggers the dispose event.

=cut

sub dispose {
	my ($self) = @_;
	$self->unregister;
	$self->trigger('dispose', {});
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
