package Eldhelm::Server::Shedule;

use strict;
use Carp;
use Carp qw(longmess);
use Data::Dumper;
use Date::Calc qw(Date_to_Time Time_to_Date Add_Delta_YMDHMS Today Today_and_Now);
use Date::Format;

use base qw(Eldhelm::Server::BaseObject);

sub worker {
	my ($self) = @_;
	return Eldhelm::Server::Child->instance;
}

sub validate {
	my ($self, $rule) = @_;
	my ($time, $interval) = $self->readTime($rule);
	return $time;
}

sub readTime {
	my ($self, $rule) = @_;
	my ($time, $interval) = (0);
	if ($rule =~ /^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):?(\d*)$/) {
		$time = Date_to_Time($1, $2, $3, $4, $5, $6 || 0);
		$time = 0 if $time <= $self->curTime;
	} elsif ($rule =~ /^(\d+):(\d+):?(\d*)$/) {
		$time = Date_to_Time(Today(), $1, $2, $3 || 0);
		$interval = [ 0, 0, 1, 0, 0, 0 ];
	} elsif ($rule =~ /^(\d+)h/) {
		$time = $self->curTime;
		$interval = [ 0, 0, 0, $1, 0, 0 ];
	} elsif ($rule =~ /^(\d+)m/) {
		$time = $self->curTime;
		$interval = [ 0, 0, 0, 0, $1, 0 ];
	} elsif ($rule =~ /^(\d+)s/) {
		$time = $self->curTime;
		$interval = [ 0, 0, 0, 0, 0, $1 ];
	} elsif ($rule > 0) {
		$time = $self->curTime;
		$interval = [ 0, 0, 0, 0, 0, int($rule) ];
	}
	return ($time, $interval);
}

sub init {
	my ($self) = @_;
	my ($rule, $name, $action, $uid)   = $self->getList("shedule", "name", "action", "uid");
	my $logRec = "$uid($name) for $rule $action";
	$self->worker->log("Initialize shedule $logRec");

	my ($time, $interval) = $self->readTime($rule);
	$self->setHash(
		time     => $time,
		interval => $interval,
		inited   => 1,
	);
	unless ($time) {
		$self->worker->error("Unable to set shedule $logRec");
		$self->set("wait", 1);
	}
	$self->nextTime if $time <= $self->curTime;

	return $self;
}

sub isTime {
	my ($self) = @_;
	lock($self);
	return unless $self->{time};
	$self->{remain} = $self->{time} - $self->curTime;
	return if $self->{wait} || $self->{remain} >= 0;
	$self->{wait} = 1;
	return 1;
}

sub job {
	my ($self) = @_;
	return unless $self->get("wait");
	$self->setTime();

	return {
		job    => "handleAction",
		action => $self->get("action"),
		data   => $self->clone("data"),
	};
}

sub setTime {
	my ($self) = @_;
	$self->setHash(
		wait => 0,
		time => $self->nextTime,
	);
}

sub nextTime {
	my ($self) = @_;
	lock($self);
	return 0 unless $self->{interval};
	return $self->{time} = Date_to_Time(Add_Delta_YMDHMS(Time_to_Date($self->{time}), @{ $self->{interval} }));
}

sub curTime {
	return Date_to_Time(Today_and_Now());
}

sub dispose {
	my ($self) = @_;
	$self->set("disposed", 1);
	return $self;
}

1;
