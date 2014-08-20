package Eldhelm::Application::Controller::Monitoring::Heartbeat;

use strict;
use Data::Dumper;
use Eldhelm::Util::PlainCommunication;

use base qw(Eldhelm::Basic::Controller);

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Basic::Controller->new(%args);
	bless $self, $class;

	return $self;
}

sub sendHeartbeat {
	my ($self) = @_;
	
	my ($host, $port) = $self->worker->getConfigList("server.monitoring.heartbeat.host", "server.monitoring.heartbeat.port");
	eval {
		Eldhelm::Util::PlainCommunication->send($host, $port, $self->{data}{message});
	};
	$self->worker->error("Failed to send heartbeat: $@") if $@;
}

1;