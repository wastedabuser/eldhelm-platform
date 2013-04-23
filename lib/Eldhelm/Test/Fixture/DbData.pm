package Eldhelm::Test::Fixture::DbData;

use strict;
use Carp;
use Eldhelm::Database::Pool;

sub new {
	my ($class, %args) = @_;
	my $self = {
		%args,
		dbPool => Eldhelm::Database::Pool->new,
		data   => {},
	};
	bless $self, $class;

	return $self;
}

sub populate {
	my ($self, $data) = @_;
	$self->populateSatetment($_) foreach @$data;
	return;
}

sub getStatementData {
	my ($self, $st) = @_;
	my $data = $st->[1];
	$data = $data->($self, $self->{data}) if ref $data eq "CODE";
	return $data;
}

sub populateSatetment {
	my ($self, $st) = @_;

	my $sql   = $self->{dbPool}->getDb;
	my $data  = $self->getStatementData($st);
	my $table = $st->[0];

	eval {
		if (ref $data eq "HASH")
		{
			$self->insertRecord($sql, $table, $data);
		} elsif (ref $data eq "ARRAY") {
			$self->insertRecord($sql, $table, $_) foreach @$data;
		}
	};

	confess $@ if $@ && $@ !~ /Duplicate entry .* for key 'PRIMARY'/;

	return;
}

sub insertRecord {
	my ($self, $sql, $table, $data) = @_;
	my $id = $data->{id};
	if ($id && $sql->fetchScalar("SELECT 1 FROM `$table` WHERE id = ?", $id)) {
		$sql->updateRow($table, $data, { id => $id });
	} else {
		$id = $sql->insertRow($table, $data);
	}

	push @{ $self->{data}{$table} },
		{
		id => $id,
		%$data,
		};
}

sub desolate {
	my ($self, $data) = @_;
	$self->desolateSatetment($_) foreach @$data;
	return;
}

sub desolateSatetment {
	my ($self, $st) = @_;

	my $sql  = $self->{dbPool}->getDb;
	my $data = $self->getStatementData($st);

	if (ref $data eq "HASH") {
		$sql->deleteRow($st->[0], $data);
	}

	return;
}

1;
