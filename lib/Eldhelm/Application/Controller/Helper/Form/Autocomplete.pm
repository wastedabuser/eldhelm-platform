package Eldhelm::Application::Controller::Helper::Form::Autocomplete;

use strict;
use Data::Dumper;
use Eldhelm::Database::Pool;

use base qw(Eldhelm::Basic::Controller);

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->export("getData", "getRow");
	$self->public("getData", "getRow");

	return $self;
}

sub getData {
	my ($self) = @_;
	my ($conn, $data) = ($self->{connection}, $self->{data});
	my $session = $conn->getSession;

	my ($t, $k, $v) = map { s/[^a-z0-9_]//gi; $_ } split /,/, $data->{args};
	my $sql = Eldhelm::Database::Pool->new->getDb;

	$self->responseWriteJson(
		$sql->fetchArray(
			"SELECT $k as `id`, $v as `label` FROM `$t` WHERE $k = ? OR $v LIKE ? LIMIT 20",
			$data->{term}, 
			"%$data->{term}%"
		)
	);
}

sub getRow {
	my ($self) = @_;
	my ($conn, $data) = ($self->{connection}, $self->{data});
	my $session = $conn->getSession;

	my ($t, $k, $v) = map { s/[^a-z0-9_]//gi; $_ } split /,/, $data->{args};
	my $sql = Eldhelm::Database::Pool->new->getDb;

	$self->responseWriteJson(
		$sql->fetchRow(
			"SELECT $k as `id`, $v as `label` FROM `$t` WHERE $k = ?",
			$data->{value}
		)
	);
}

1;
