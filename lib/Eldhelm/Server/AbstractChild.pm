package Eldhelm::Server::AbstractChild;

use strict;
use threads;
use threads::shared;
use Data::Dumper;
use Time::HiRes;
use Carp;
use Carp qw(longmess);
use Eldhelm::Util::Factory;
use Eldhelm::Server::Router;
use Eldhelm::Util::Tool;
use Eldhelm::Server::Shedule;

my $instance;

sub instance {
	return $instance;
}

sub addInstance {
	my ($self) = @_;
	$instance = $self;
}

# =================================
# Persist
# =================================

sub config {
	my ($self) = @_;
	return $self->{configObject} if $self->{configObject};

	lock($self->{config});
	return $self->{configObject} =
		Eldhelm::Util::Factory->instanceFromScalar("Eldhelm::Server::BaseObject", $self->{config});
}

sub getConfig {
	my ($self, $property) = @_;
	return $self->config->clone($property);
}

sub getConfigList {
	my ($self, @list) = @_;
	return $self->config->getList(@list);
}

sub stash {
	my ($self) = @_;
	return $self->{stashObject} if $self->{stashObject};

	lock($self->{stash});
	return $self->{stashObject} =
		Eldhelm::Util::Factory->instanceFromScalar("Eldhelm::Server::BaseObject", $self->{stash});
}

sub registerPersist {
	my ($self, $args) = @_;

	confess "Can not register presistent object without id" if !$args->{id};
	confess "Can not register presistent object without id" if !$args->{persistType};
	my $persistData = shared_clone($args);

	{
		my $per = $self->{persists};
		lock($per);

		$per->{ $args->{id} } = $persistData;
	}

	{
		my $perTp = $self->{persistsByType};
		lock($perTp);

		my $perTps = $perTp->{ $args->{persistType} } ||= shared_clone({});
		$perTps->{ $args->{id} } = 1;
	}

	return $persistData;
}

sub unregisterPersist {
	my ($self, $persist) = @_;

	confess "A persist object should be supplied" if !ref $persist;
	my ($id, $type) = $persist->getList("id", "persistType");

	{
		my $per = $self->{persists};
		lock($per);

		delete $per->{$id};
	}

	{
		my $perTp = $self->{persistsByType};
		lock($perTp);

		my $perTps = $perTp->{$type};
		delete $perTps->{$id} if $perTps;
	}

	return $self;
}

sub getPersist {
	my ($self, $id) = @_;
	return if !$id;

	my $persistData;
	{
		my $per = $self->{persists};
		lock($per);
		$persistData = $per->{$id};
	}
	return if !$persistData;
	lock($persistData);

	confess "The persist object does not contain the persistType property"
		if !$persistData->{persistType};
	$persistData->{updatedon} = time;
	return Eldhelm::Util::Factory->instanceFromScalar($persistData->{persistType}, $persistData);
}

sub getPersistFromRef {
	my ($self, $persistData) = @_;
	lock($persistData);

	return Eldhelm::Util::Factory->instanceFromScalar($persistData->{persistType}, $persistData);
}

sub hasPersist {
	my ($self, $id) = @_;
	my $per = $self->{persists};
	lock($per);

	return $per->{$id} ? 1 : undef;
}

sub getPersistId {
	my ($self, $var, @values) = @_;
	my $lkp = $self->{persistLookup};
	lock($lkp);

	my (@list, $sessId);
	foreach (@values) {
		$sessId = $lkp->{"$var-$_"};
		push @list, $sessId if $sessId;
	}
	return @list > 1 ? @list : $list[0] || ();
}

sub findPersist {
	my $self = shift;
	my @list = map { $self->getPersist($_) || () } $self->getPersistId(@_);
	return @list > 1 ? @list : $list[0] || ();
}

sub findAndFilterPersist {
	my ($self, $var, $values, $filter) = @_;
	my @list = $self->getPersistId($var, @$values);
	return $self->filterPersist($filter, \@list);
}

sub filterPersist {
	my ($self, $filter, $ids) = @_;
	my $per = $self->{persists};
	my @list;
	if ($ids) {
		@list = @$ids;
	} else {
		lock($per);
		@list = keys %$per;
	}

	my $i;
	my @filterKeys = keys %$filter;
	my @result;
	foreach my $s (@list) {
		my $pItem;
		{
			lock($per);
			$pItem = $per->{$s};
		}
		next unless $pItem;

		$i = 0;
		{
			lock($pItem);
			foreach my $fk (@filterKeys) {
				$i++ if defined($pItem->{$fk}) && $pItem->{$fk} eq $filter->{$fk};
			}
		}
		push @result, $s if @filterKeys == $i;
	}
	return map { $self->getPersist($_) || () } @result;
}

sub getPersistsByType {
	my ($self, $type, $filter) = @_;
	my @list;
	{
		my $per = $self->{persistsByType};
		lock($per);

		my $pmap = $per->{$type} || {};
		@list = keys %$pmap;
	}

	return $self->filterPersist($filter, \@list)
		if $filter;

	return map { $self->getPersist($_) || () } @list;
}

sub registerPersistLookup {
	my ($self, $id, @vars) = @_;
	my $plkp = $self->{persistLookup};
	lock($plkp);

	my $key = join "-", @vars;
	$plkp->{$key} = $id;

	return $key;
}

sub unregisterPersistLookup {
	my ($self, @vars) = @_;
	my $plkp = $self->{persistLookup};
	lock($plkp);

	my $key = join "-", @vars;
	delete $plkp->{$key};

	return $key;
}

sub delay {
	my ($self, $interval, $handle, $args, $persistId) = @_;
	my $devs = $self->{delayedEvents};
	lock($devs);

	my $stamp = time + $interval;
	my $list  = $devs->{$stamp};
	$list = $devs->{$stamp} = shared_clone([]) if !$list;

	my $num = scalar @$list;
	push @$list,
		shared_clone(
		{   persistId => $persistId,
			stamp     => $stamp,
			handle    => $handle,
			args      => $args,
		}
		);

	return "$stamp-$num";
}

sub cancelDelay {
	my ($self, $delayId) = @_;

	my ($stamp, $num) = split /-/, $delayId;
	return $self if !$stamp || !defined $num;

	my $devs = $self->{delayedEvents};
	lock($devs);

	my $list = $devs->{$stamp};
	return $self unless $list;

	$list->[$num]{canceled} = 1;

	return $self;
}

sub doJob {
	my ($self, $job) = @_;
	if (!$job->{job}) {
		$self->error("Can not execute a job without a job name:\n".Dumper($job));
		return;
	}

	my $queue = $self->{jobQueue};
	lock($queue);

	push @$queue, shared_clone({ %$job, proto => "System" });

	return $self;
}

sub doAction {
	my ($self, $action, $data) = @_;
	return $self->doJob(
		{   job    => "handleAction",
			action => $action,
			data   => $data,
		}
	);
}

sub getShedule {
	my ($self, $name) = @_;
	my $s;
	{
		my $se = $self->{sheduledEvents};
		lock($se);
		$s = $se->{$name};
	}
	return unless $s;
	return Eldhelm::Util::Factory->instanceFromScalar("Eldhelm::Server::Shedule", $s);
}

sub setShedule {
	my ($self, $name, $shedule, $action, $data) = @_;
	my $se = $self->{sheduledEvents};

	lock($se);
	$se->{$name} = shared_clone(
		{   name    => $name,
			shedule => $shedule,
			action  => $action,
			data    => $data,
		}
	);

	return $self;
}

# =================================
# Utility
# =================================

sub log {
	my ($self, $msg, $type) = @_;
	$type ||= "general";
	my $queue = $self->{logQueue}{$type};
	return if !$queue;

	lock($queue);
	my $tm = Time::HiRes::time;
	push @$queue, "~$tm~".($self->{id} ? "Worker $self->{id}: $msg" : $msg);
	return $self;
}

sub debug {
	my ($self, $msg) = @_;
	$self->log($msg, "debug");
}

sub access {
	my ($self, $msg) = @_;
	$self->log($msg, "access");
}

sub error {
	my ($self, $msg) = @_;
	$self->log($msg, "error");
}

sub message {
	my ($self, $msg) = @_;
	$self->log($msg, "message");
}

1;
