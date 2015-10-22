package Eldhelm::Server::Logger;

use strict;
use threads;
use threads::shared;
use Data::Dumper;
use Time::HiRes qw(usleep);
use Date::Format;
use Carp;

use base qw(Eldhelm::Server::Child);

sub create {
	my (%args) = @_;
	Eldhelm::Server::Logger->new(%args);
}

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Server::Child->instance;
	if (ref $self ne "Eldhelm::Server::Logger") {
		$self = Eldhelm::Server::Child->new(%args);
		bless $self, $class;

		$self->addInstance;
		$self->init;
		$self->run;
	}
	return $self;
}

sub init {
	my ($self) = @_;
	$self->{$_} = $self->getConfig("server.logger.$_") foreach qw(interval logs);
	$self->{interval} = 1000 * ($self->{interval} || 250);
	foreach my $type (keys %{ $self->{logs} }) {
		foreach my $path (@{ $self->{logs}{$type} }) {
			if ($path ne 'stderr' && $path ne 'stdout' && !-f $path) {
				open FW, '>', $path or confess "Can not write log file $path: $!";
				close FW;
			}
		}
	}
	{
		my $lq = $self->{logQueue};
		lock($lq);
		$self->{queues} = [ keys %$lq ];
	}
}

# =================================
# Tasks
# =================================

sub run {
	my ($self) = @_;
	$self->status("action", "run");

	while (1) {
		foreach my $q (@{ $self->{queues} }) {
			my @data = $self->fetchTask($q);
			if ($q eq "threadCmdQueue") {
				$self->systemTask(\@data);
				next;
			}
			$self->runTask($q, \@data) if @data;
		}
		usleep($self->{interval});
	}
}

sub fetchTask {
	my ($self, $type) = @_;
	my $queue = $self->{logQueue}{$type};
	lock($queue);

	my @data = @$queue;
	@$queue = ();
	return @data;
}

sub systemTask {
	my ($self, $data) = @_;
	foreach (@$data) {
		$self->exitLogger  if $_ eq "exitWorker";
		$self->reconfigure if $_ eq "reconfig";
	}
}

sub runTask {
	my ($self, $type, $data) = @_;
	foreach my $path (@{ $self->{logs}{$type} }) {
		if ($path eq "stdout") {
			print $self->createRecord("$type: $_\n") foreach @$data;
		} elsif ($path eq "stderr") {
			warn $self->createRecord("$type: $_") foreach @$data;
		} else {
			if (open FW, ">>$path") {
				print FW $self->createRecord("$_\n") foreach @$data;
				close FW;
			} else {
				warn "Can not write '$path': $!";
			}
		}
	}
	return;
}

sub createRecord {
	my ($self, $msg) = @_;
	$msg =~ s/~(.*?)~//;
	my ($time) = $1;
	(my $mk = $time - int $time) =~ s/^0.(\d{3}).*$/$1/;
	$mk = "000" if $mk < 1;
	return time2str("%d.%m.%Y %T ${mk}ms", $time).": $msg";
}

sub exitLogger {
	my ($self) = @_;
	print "Exitting logger ...\n";
	$self->status("action", "exit");
	usleep(10_000);
	threads->exit();
}

sub reconfigure {
	my ($self) = @_;
	print "Reconfiguring logger ...\n";
	$self->init;
}

1;
