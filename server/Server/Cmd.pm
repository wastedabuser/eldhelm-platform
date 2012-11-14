package Eldhelm::Server::Cmd;

use strict;
use Eldhelm::Server::Message::Json;

sub new {
	my ($class, %args) = @_;
	my $self = { reader => Eldhelm::Server::Message::Json->new };
	bless $self, $class;

	return $self;
}

sub login {
	my ($self, $user, $pass) = @_;
	return $self->{reader}->write(
		{   type    => "auth",
			command => "login",
			data    => {
				name => $user,
				pass => $pass,
			}
		}
	);
}

sub chatTo {
	my ($self, $user, $msg) = @_;
	return $self->{reader}->write(
		{   type    => "chat",
			command => "send",
			data    => {
				to      => $user,
				message => $msg,
			}
		}
	);
}

# =====================
# Game
# =====================

sub startQuickGameSearch {
	my ($self) = @_;
	return $self->{reader}->write(
		{   type    => "play",
			command => "startQuickGameSearch",
			data => {
				heroId => 3
			}
		}
	);
}

sub readyToStart {
	my ($self) = @_;
	return $self->{reader}->write(
		{   type    => "play",
			command => "readyToStart",

		}
	);
}

sub doneLoadingTable {
	my ($self) = @_;
	return $self->{reader}->write(
		{   type    => "play",
			command => "doneLoadingTable",

		}
	);
}

sub donePhase {
	my ($self) = @_;
	return $self->{reader}->write(
		{   type    => "play",
			command => "donePhase",

		}
	);
}

1;
