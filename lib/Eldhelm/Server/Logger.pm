package Eldhelm::Server::Logger;

use strict;
use threads;
use threads::shared;
use Thread::Suspend;
use Data::Dumper;
use Time::HiRes;
use Date::Format;
use Carp;

sub create {
	my (@args) = @_;
	Eldhelm::Server::Logger->new(@args);
}

my $instance;

sub new {
	my ($class, %args) = @_;
	if (!defined $instance) {
		$instance = {
			info     => $args{info},
			config   => $args{config},
			logQueue => $args{logQueue},
			id       => threads->tid
		};
		bless $instance, $class;

		$instance->init;
		$instance->run;
	}
	return $instance;
}

sub init {
	my ($self) = @_;
	lock($self->{config});
	
	$self->{$_} = $self->{config}{server}{logger}{$_} foreach qw(interval logs);
	$self->{interval} = 1000 * ($self->{interval} || 250);
}

# =================================
# Tasks
# =================================

sub run {
	my ($self) = @_;
	my @queues = keys %{ $self->{logQueue} };
	my $interval = $self->{interval};
	while (1) {
		foreach (@queues) {
			my @data = $self->fetchTask($_);
			$self->runTask($_, @data) if @data;
		}
		Time::HiRes::usleep($interval);
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
