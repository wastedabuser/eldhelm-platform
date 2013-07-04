package Eldhelm::Server::Shedule;

use strict;
use Carp;
use Carp qw(longmess);
use Data::Dumper;
use Date::Calc qw(Date_to_Time Time_to_Date Add_Delta_YMDHMS Today Today_and_Now);
use Date::Format;

sub new {
	my ($class, %args) = @_;
	my $self = { interval => [ 0, 0, 0, 0, 0, 0 ], };
	bless $self, $class;

	$self->init($args{init}) if $args{init};

	return $self;
}

sub worker {
	my ($self) = @_;
	return Eldhelm::Server::Child->instance;
}

sub init {
	my ($self, $data) = @_;
	$self->setRule($data->[0]);
	($self->{action}, $self->{data}) = @$data[ 1 .. 2 ];
	return $self;
}

sub setRule {
	my ($self, $rule) = @_;
	if ($rule =~ /^(\d+):(\d+):?(\d*)$/) {
		$self->{time} = Date_to_Time(Today(), $1, $2, $3 || 0);
		$self->{interval} = [ 0, 0, 1, 0, 0, 0 ];
	} elsif ($rule =~ /^(\d+)h/) {
		$self->{time} = $self->curTime;
		$self->{interval} = [ 0, 0, 0, $1, 0, 0 ];
	} elsif ($rule =~ /^(\d+)m/) {
		$self->{time} = $self->curTime;
		$self->{interval} = [ 0, 0, 0, 0, $1, 0 ];
	} elsif ($rule =~ /^(\d+)s/) {
		$self->{time} = $self->curTime;
		$self->{interval} = [ 0, 0, 0, 0, 0, $1 ];
	} elsif ($rule > 0) {
		$self->{time} = $self->curTime;
		$self->{interval} = [ 0, 0, 0, 0, 0, int($rule) ];
	} else {
		$self->worker->error("Unable to set shedule rule for: $rule");
		$self->{wait} = 1;
	}
	$self->nextTime if $self->{time} <= $self->curTime;
}

sub isTime {
	my ($self) = @_;
	$self->{remain} = $self->{time} - $self->curTime;
	return if $self->{wait} || $self->{remain} >= 0;
	$self->{wait} = 1;
	return 1;
}

sub job {
	my ($self) = @_;
	return unless $self->{wait};
	$self->setTime();
	return {
		job    => "handleAction",
		action => $self->{action},
		data   => $self->{data},
	};
}

sub setTime {
	my ($self) = @_;
	$self->{wait} = 0;
	$self->{time} = $self->nextTime;
}

sub nextTime {
	my ($self) = @_;
	return $self->{time} = Date_to_Time(Add_Delta_YMDHMS(Time_to_Date($self->{time}), @{ $self->{interval} }));
}

sub curTime {
	return Date_to_Time(Today_and_Now());
}

1;
