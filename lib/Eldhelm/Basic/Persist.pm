package Eldhelm::Basic::Persist;

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

use base qw(Eldhelm::Server::BaseObject);

my $instanceIndex = 0;

sub new {
	my ($class, %args) = @_;
	my %data = (
		%args,
		id => $args{id} || createId(),
		timeout                   => $class->worker->getConfig("server.garbageCollect.persists"),
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

sub getModel {
	my ($self, $model, $args) = @_;
	$args ||= {};
	return Eldhelm::Util::Factory->instanceFromNotation("Eldhelm::Application::Model", $model, %$args);
}

sub createId {
	$instanceIndex++;
	return Digest::MD5->new->add(time."i".$instanceIndex)->hexdigest;
}

sub register {
	my ($self) = @_;

	my @props = $self->getPureList("lookupProperties");
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

	$self->worker->unregisterPersistLookup($_) foreach $self->getHashrefKeys("__persistLookupProperties");
	$self->worker->unregisterPersist($self);

	return $self;
}

sub id {
	my ($self) = @_;
	return $self->get("id");
}

sub call {
	my ($self, $fn, @data) = @_;
	return $self->$fn(@data) if $self->can($fn);
	return;
}

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

	my $events = $self->get("__events");
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

sub unbind {
	my ($self, $type, $id) = @_;
	my $events = $self->get("__events");

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

sub trigger {
	my ($self, $type, $options) = @_;
	my $events = $self->get("__events");
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
		my ($ev, $id);
		my @ids = keys %$tpEvents;
		foreach $id (@ids) {
			$ev = $tpEvents->{$id};
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

sub delay {
	my ($self, $interval, $handle, $args) = @_;
	return $self->worker->delay($interval, $handle, $args, $self->id);
}

sub cancelDelay {
	my ($self, $delayId) = @_;
	$self->worker->cancelDelay($delayId);
	return $self;
}

sub beforeSaveState {
	my ($self) = @_;

}

sub dispose {
	my ($self) = @_;
	$self->unregister;
	$self->trigger("dispose", {});
	return;
}

1;
