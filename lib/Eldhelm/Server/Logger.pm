package Eldhelm::Server::Logger;

use strict;
use threads;
use threads::shared;
use Data::Dumper;
use Time::HiRes;
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
}

# =================================
# Tasks
# =================================

sub run {
	my ($self)   = @_;
	my @queues   = keys %{ $self->{logQueue} };
	my $interval = $self->{interval};
	loggermain: while (1) {
		foreach (@queues) {
			my @data = $self->fetchTask($_);
			last loggermain if $_ eq "threadCmdQueue" && $data[0] eq "exitWorker";
			$self->runTask($_, @data) if @data;
		}
		Time::HiRes::usleep($interval);
	}
	
	print "Exitting logger ...\n";
	$self->status("action", "exit");
	threads->exit();
}

sub fetchTask {
	my ($self, $type) = @_;
	my $queue = $self->{logQueue}{$type};
	lock($queue);
	my @data = @$queue;
	@$queue = ();
	return @data;

}

sub runTask {
	my ($self, $type, @data) = @_;
	foreach my $path (@{ $self->{logs}{$type} }) {
		if ($path eq "stdout") {
			print $self->createRecord("$type: $_\n") foreach @data;
		} elsif ($path eq "stderr") {
			warn $self->createRecord("$type: $_") foreach @data;
		} else {
			if (open FW, ">>$path") {
				print FW $self->createRecord("$_\n") foreach @data;
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

1;
