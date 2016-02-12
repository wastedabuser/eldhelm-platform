package Eldhelm::Database::Pool;

use strict;
use Eldhelm::Server::Child;
use Eldhelm::Database::MySql;

my $isntance;

sub new {
	my ($class, %args) = @_;
	if (!defined $isntance) {
		$isntance = {
			config      => $args{config},
			worker      => Eldhelm::Server::Child->instance,
			connections => {}
		};
		bless $isntance, $class;
	}
	return $isntance;
}

sub getDb {
	my ($self, $name) = @_;
	$name ||= '_default';
	if (!$self->{connections}{$name}) {
		my $config = $self->{config}{mysql} || $self->{worker}->getConfig('mysql');
		$self->{connections}{$name} = Eldhelm::Database::MySql->new(%{ $config->{$name} });
	}
	$self->{connections}{$name}->connect if !$self->{connections}{$name}->isConnected;
	return $self->{connections}{$name};
}

sub getDbh {
	my ($self) = @_;
	return $self->getDb->dbh;
}

1;
