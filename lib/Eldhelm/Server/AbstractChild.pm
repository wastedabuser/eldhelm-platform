package Eldhelm::Server::AbstractChild;

=pod

=head1 NAME

Eldhelm::Server::AbstractChild - A base class for a thread wrapper object.

=head1 SYNOPSIS

This class should not be constructed directly.

=head1 DESCRIPTION

A thread wrapper class.

=head1 METHODS

=over

=cut

use strict;

use threads;
use threads::shared;
use Data::Dumper;
use Time::HiRes;
use Carp qw(confess longmess);
use Eldhelm::Server::Router;
use Eldhelm::Server::Shedule;
use Eldhelm::Util::Factory;
use Eldhelm::Util::Tool;
use Eldhelm::Util::ExternalScript;

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

=item config() Eldhelm::Server::BaseObject

Returns an interface object (L<Eldhelm::Server::BaseObject>) to access the current server configuration. It is accessible for both read and write.

=cut

sub config {
	my ($self) = @_;
	return $self->{configObject} if $self->{configObject};

	lock($self->{config});
	return $self->{configObject} =
		Eldhelm::Util::Factory->instanceFromScalar('Eldhelm::Server::BaseObject', $self->{config});
}

=item getConfig($property) Mixed

Returns a clone of a node in the configuration file descrubed by a dotted notaion.

C<$property> String - dotted notation;

	my $name = $self->getConfig('server.name');

=cut

sub getConfig {
	my ($self, $property) = @_;
	return $self->config->clone($property);
}

=item getConfigList(@list) Mixed

Returns a list of nodes from the configuration file descrubed by a dotted notaions.

C<@List> Array - a list of dotted notations;

	my ($name, $host) = 
		$self->getConfigList('server.name', 'server.host');

=cut

sub getConfigList {
	my ($self, @list) = @_;
	return $self->config->getList(@list);
}

=item stash() Eldhelm::Server::BaseObject

This is a general purpose storage. Something like a local storage or a static persistant storage.
It is accessed via L<Eldhelm::Server::BaseObject> so it works like any other persistant object.

=cut

sub stash {
	my ($self) = @_;
	return $self->{stashObject} if $self->{stashObject};

	lock($self->{stash});
	return $self->{stashObject} =
		Eldhelm::Util::Factory->instanceFromScalar('Eldhelm::Server::BaseObject', $self->{stash});
}

sub registerPersist {
	my ($self, $args) = @_;

	confess 'Can not register presistent object without id'          unless $args->{id};
	confess 'Can not register presistent object without persistType' unless $args->{persistType};
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

	confess 'A persist object must be supplied' unless ref $persist;
	my ($id, $type) = $persist->getList('id', 'persistType');

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

=item getPersist($id) Eldhelm::Basic::Persist

Finds a persistant object by id.

C<$id> String - the id of the persistant object;

=cut

sub getPersist {
	my ($self, $id) = @_;
	return unless $id;

	my $persistData;
	{
		my $per = $self->{persists};
		lock($per);
		$persistData = $per->{$id};
	}
	return unless $persistData;
	lock($persistData);

	confess 'The persist object does not contain the persistType property'
		unless $persistData->{persistType};
	$persistData->{updatedon} = time;
	return Eldhelm::Util::Factory->instanceFromScalar($persistData->{persistType}, $persistData);
}

sub getPersistFromRef {
	my ($self, $persistData) = @_;
	lock($persistData);

	return Eldhelm::Util::Factory->instanceFromScalar($persistData->{persistType}, $persistData);
}

=item hasPersist($id) 1 or undef

Checks whether a persistant object exists.

C<$id> String - the id of the persistant object;

=cut

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

=item findAndFilterPersist($var, $values, $filter) Array

Finds objects by property matching a list of values. The optionally filters them.

C<$var> String - A property name;
C<$values> ArrayRef - A list of property values;
C<$filter> HashRef - Optional; Properties to be matched on the persistant objects;

	$self->findAndFilterPersist(
		'playerId',
		[1, 2, 3],
		{
			connected => 1
		}
	);

=cut

sub findAndFilterPersist {
	my ($self, $var, $values, $filter) = @_;
	my @list = $self->getPersistId($var, @$values);
	return $self->filterPersist($filter, \@list);
}

=item filterPersist($filter, $ids) Array

Checks whether a persistant object exists.

C<$filter> HashRef - Properties to be matched on the persistant objects;
C<$ids> ArrayRef - optional; A ist of ids. If ommited all persistant objects are filtered;

	$self->filterPersist({
		connected => 1
	});
	
	# or filter a specific set
	$self->filterPersist({
		connected => 1
	}, [1, 2, 3, 4])

=cut

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

=item getPersistsByType($type, $filter) Array

Gets all persistant objects by type and then optionally filters them.

C<$type> String - The type of the objects as a package name;
C<$fitler> $filter - Optional; Properties to be matched on the persistant objects;

	$self->getPersistsByType(
		'Eldhelm::Server::Session',
		{
			connected => 1
		}
	);

=cut

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

	my $key = join '-', @vars;
	$plkp->{$key} = $id;

	return $key;
}

sub unregisterPersistLookup {
	my ($self, @vars) = @_;
	my $plkp = $self->{persistLookup};
	lock($plkp);

	my $key = join '-', @vars;
	delete $plkp->{$key};

	return $key;
}

sub getPersistCount {
	my ($self) = @_;
	my $cnt;
	{
		my $per = $self->{persists};
		lock($per);
		$cnt = keys %$per;
	}
	return $cnt;
}

sub getPersistCountByType {
	my ($self, $type) = @_;
	my $cnt;
	{
		my $per = $self->{persistsByType};
		lock($per);
		my $pmap = $per->{$type} || {};
		$cnt = keys %$pmap;
	}
	return $cnt;
}

sub doJob {
	my ($self, $job) = @_;
	if (!$job->{job}) {
		$self->error("Can not execute a job without a job name:\n".Dumper($job));
		return;
	}

	return push @{ $self->{jobQueue} }, shared_clone({ %$job, proto => 'System' });
}

=item doAction($action, $data)

Appends and action to be executed by the server task queue.

C<$action> String - Dotted notation of a controller action;
C<$data> HashRef -  Context data to be used when executing the controller;

=cut

sub doAction {
	my ($self, $action, $data) = @_;
	return $self->doJob(
		{   job    => 'handleAction',
			action => $action,
			data   => $data,
		}
	);
}

=item getShedule($name) Eldhelm::Server::Shedule

Returns a L<Eldhelm::Server::Shedule> object by name. This object coordinates the execution of a scheduled task;

C<$name> String - The name of the scheduled task;

=cut

sub getShedule {
	my ($self, $name) = @_;
	my $s;
	{
		my $se = $self->{sheduledEvents};
		lock($se);
		$s = $se->{$name};
	}
	return unless $s;
	return Eldhelm::Util::Factory->instanceFromScalar('Eldhelm::Server::Shedule', $s);
}

=item getShedule($name, $schedule, $action, $data) self

Registers a new scheduled task.

C<$name> String - A string indicating the sheduled task;
C<$schedule> String - A string indicating when the task should be executed;
C<$action> String - The controller action to be called;
C<$data> HashRef - The context data when the action is called;

=cut

sub setShedule {
	my ($self, $name, $shedule, $action, $data) = @_;

	my $prevShedule = $self->getShedule($name);
	$prevShedule->dispose if $prevShedule;

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

=item removeShedule($name) self

Removes a scheduled task by name;

C<$name> String - The name of the scheduled task;

=cut

sub removeShedule {
	my ($self, $name) = @_;

	my $prevShedule = $self->getShedule($name);
	$prevShedule->dispose if $prevShedule;

	my $se = $self->{sheduledEvents};
	lock($se);
	delete $se->{$name};

	return $self;
}

### UNIT TEST: 303_external_script.pl ###

sub createExternalScriptCommand {
	my ($self, $name, $args) = @_;

	my $homePath   = $self->getConfig('server.serverHome');
	my $scriptFile = "$homePath/script/$name.pl";
	unless (-f $scriptFile) {
		$self->error("Script not found: $scriptFile");
		return ();
	}

	my $compiledArgs = Eldhelm::Util::ExternalScript->encodeArg($args || []);
	return ($scriptFile, qq~perl $scriptFile "$self->{configPath}" "$compiledArgs"~);
}

=item runExternalScript($name, $args) Mixed

Runs a task in an external script and captures the result.

C<$name> String - The script name
C<$args> HashRef or ArrayRef - The script arguments

Sometimes you have to run non-thread safe code or a non-thread safe library.
This can do this using this utility. It provides a easy to use interface to run external scripts.
Please, see L<Eldhelm::Util::ExternalScript> for more information of how to write your scripts.

=cut

### UNIT TEST: 304_worker_external_script.pl ###

sub runExternalScript {
	my ($self, $name, $args) = @_;

	my ($scriptFile, $cmd) = $self->createExternalScriptCommand($name, $args);
	return unless $scriptFile;

	my $result;
	eval {
		$self->access($cmd);
		$result = Eldhelm::Util::ExternalScript->parseOutput(`$cmd`);
		1;
	} or do {
		$self->error("Unable to run script: $@");
	};

	return $result;
}

=item runExternalScriptAsync($name, $args) self

Same as L<< $self->runExternalScript >>, but the worker does not wait the script to finish and the result is not captured.

C<$name> String - The script name
C<$args> HashRef or ArrayRef - The script arguments

=cut

### UNIT TEST: 305_worker_external_script_async.pl ###

sub runExternalScriptAsync {
	my ($self, $name, $args) = @_;

	my ($scriptFile, $cmd) = $self->createExternalScriptCommand($name, $args);
	return unless $scriptFile;

	$cmd .= ' &';
	eval {
		$self->access($cmd);
		system($cmd);
		1;
	} or do {
		$self->error("Unable to run async script: $@");
	};

	return $self;
}

# =================================
# Utility
# =================================

=item log($message, $logName)

Prints a message in a log specified by name. Defaults to C<general>.

=cut

sub log {
	my ($self, $msg, $type) = @_;
	$type ||= 'general';
	my $queue = $self->{logQueue}{$type};
	return unless $queue;
	$msg = $$msg if ref $msg eq 'SCALAR';

	lock($queue);
	my $tm = Time::HiRes::time;
	push @$queue, "~$tm~".($self->{id} ? "Worker $self->{id}: $msg" : $msg);
	return $self;
}

=item debug($message)

Prints a message in the debug log.

=cut

sub debug {
	my ($self, $msg) = @_;
	$self->log($msg, 'debug');
}

=item access($message)

Prints a message in the access log.

=cut

sub access {
	my ($self, $msg) = @_;
	$self->log($msg, 'access');
}

=item error($message)

Prints a message in the error log.

=cut

sub error {
	my ($self, $msg) = @_;
	$self->log($msg, 'error');
}

sub message {
	my ($self, $msg) = @_;
	$self->log($msg, 'message');
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
