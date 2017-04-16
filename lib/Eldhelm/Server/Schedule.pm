package Eldhelm::Server::Schedule;

=pod

=head1 NAME

Eldhelm::Server::Schedule - An object controlling the schedule execution.

=head1 SYNOPSIS

You should not create this object directly. Instead do:

	$self->worker->setSchedule(
		'mySchedule',
		'15m',
		'myController:myAction',
		{ a => 1 }
	);

Please see L<Eldhelm::Server::AbstractChild>->setSchedule and the other schedule methods:

=head1 DESCRIPTION

This class has the following properties that should be accessed like this:

	my $time = $self->get('time');

=over

=item time Number

A unix timestamp indicating the next execution.

=item remain Number

Seconds remaining to the next execution.

=item interval ArrayRef

The execution interval in chunks as needed by L<Date::Calc>

=back

=head1 METHODS

=over

=cut

use strict;
use Carp;
use Carp qw(longmess);
use Data::Dumper;
use Date::Calc qw(Date_to_Time Time_to_Date Add_Delta_YMDHMS Today Today_and_Now Day_of_Week Decode_Day_of_Week Add_Delta_Days);
use Date::Format;
use Eldhelm::Server::Child;

use parent 'Eldhelm::Server::BaseObject';

sub worker {
	my ($self) = @_;
	return Eldhelm::Server::Child->instance;
}

sub validate {
	my ($self, $rule)     = @_;
	my ($time, $interval) = $self->readTime($rule);
	return $time;
}

### UNIT TEST: 600_schedule.pl ###

sub readTime {
	my ($self, $rule) = @_;

	# priority - 0 high, 1 low
	my ($time, $interval, $priority) = (0);
	my $words = join '|', qw(mon tu tue tues wed th thu thur fri sat sun);
	
	if ($rule =~ /^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):?(\d*)$/) {
		$time = Date_to_Time($1, $2, $3, $4, $5, $6 || 0);
		$time = 0 if $time <= $self->curTime;
		$priority = 1;
	} elsif ($rule =~ /^(\d+):(\d+):?(\d*)$/) {
		$time = Date_to_Time(Today(), $1, $2, $3 || 0);
		$interval = [ 0, 0, 1, 0, 0, 0 ];
		$priority = 1;
	} elsif ($rule =~ /^(\d*)($words)\s*(\d*):*(\d*):*(\d*)/) {
		my $num = $1 || 1;
		$time = Date_to_Time(Add_Delta_Days(Today(), 7 - Day_of_Week(Today()) + Decode_Day_of_Week($2)), $3 || 0, $4 || 0, $5 || 0);
		$interval = [ 0, 0, $num * 7, 0, 0, 0 ];
		$priority = 1;
	} elsif ($rule =~ /^(\d+)w/) {
		$time = $self->curTime;
		$interval = [ 0, 0, $1 * 7, 0, 0, 0 ];
	} elsif ($rule =~ /^(\d+)d/) {
		$time = $self->curTime;
		$interval = [ 0, 0, $1, 0, 0, 0 ];
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
	
	return ($time, $interval, $priority);
}

sub init {
	my ($self) = @_;
	my ($rule, $name, $action, $uid) = $self->getList('schedule', 'name', 'action', 'uid');
	my $logRec = "$uid($name) for $rule $action";
	$self->worker->log("Initialize schedule $logRec");

	my ($time, $interval, $priority) = $self->readTime($rule);
	$self->setHash(
		time     => $time,
		interval => $interval,
		priority => $priority,
		inited   => 1,
	);
	unless ($time) {
		$self->worker->error("Unable to set schedule $logRec");
		$self->set('wait', 1);
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
	return unless $self->get('wait');
	$self->setTime();

	return {
		job      => 'handleAction',
		action   => $self->get('action'),
		data     => $self->clone('data'),
		priority => $self->get('priority')
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
	return $self->{time} = $self->calcNextTime($self->{time}, $self->{interval});
}

sub calcNextTime {
	my ($self, $time, $interval) = @_;
	return Date_to_Time(Add_Delta_YMDHMS(Time_to_Date($time), @$interval));
}

sub curTime {
	return Date_to_Time(Today_and_Now());
}

sub dispose {
	my ($self) = @_;
	$self->set('disposed', 1);
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
