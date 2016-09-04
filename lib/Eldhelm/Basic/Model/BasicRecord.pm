package Eldhelm::Basic::Model::BasicRecord;

use strict;
use Data::Dumper;
use Eldhelm::Basic::Model::BasicDb;

use parent 'Eldhelm::Basic::Model';

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->{data} = $args{data};
	$self->{basicDb} ||= Eldhelm::Basic::Model::BasicDb->new(table => $args{table});

	return $self;
}

sub getInstance {
	my ($self, $filter, $args) = @_;
	my $name = ref $self;
	my $data = $self->{basicDb}->filterOne($filter);
	return if !$data;
	return $self->createInstance($data, $args);
}

sub createInstance {
	my ($self, $data, $args) = @_;
	my $name = ref $self;
	return $name->new(
		$args ? %$args : (),
		basicDb => $self->{basicDb},
		data    => $data
	);
}

sub save {
	my ($self) = @_;
	$self->setIfNot('id', $self->{basicDb}->save($self->{data}));
	return $self;
}

sub get {
	my ($self, $name) = @_;
	return $self->{data}{$name};
}

sub set {
	my ($self, $name, $value) = @_;
	$self->{data}{$name} = $value;
	return $self;
}

sub setIfNot {
	my ($self, $name, $value) = @_;
	$self->{data}{$name} ||= $value;
	return $self;
}

1;
