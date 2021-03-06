package Eldhelm::Basic::Model::BasicDb;

use strict;
use Data::Dumper;
use Eldhelm::Util::Tool;
use Eldhelm::Database::Filter;

use parent 'Eldhelm::Basic::Model';

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	bless $self, $class;

	$self->{table}        = $args{table};
	$self->{pkFields}     = $args{pkFields} || ['id'];
	$self->{customFields} = $args{customFields} || {};
	$self->{defaultOrder} = $args{defaultOrder} || [];

	return $self;
}

sub desc {
	my ($self) = @_;
	my $sql = $self->{dbPool}->getDb;
	return $sql->desc($self->{table});
}

sub createSelectQuery {
	my ($self, $what, $where, $order, $limit) = @_;

	return "SELECT $what FROM `$self->{table}` t WHERE $where $order $limit";
}

sub createDeleteQuery {
	my ($self, $where, $limit) = @_;

	return "DELETE FROM `$self->{table}` WHERE $where $limit";
}

sub chooseFields {
	my ($self, $fields) = @_;
	if (ref $fields eq 'ARRAY') {
		return join ',', map { "t.`$_`" } @$fields;
	} elsif (ref $fields eq 'HASH') {
		return join ',', map { "t.`$_` AS ".$fields->{$_} } keys %$fields;
	}
	return '';
}

sub fieldList {
	my ($self, $fields, $key) = @_;
	$key ||= 'id';
	push @$fields, $key if $key && $fields && grep { $_ ne $key } @$fields;
	return $key;
}

sub setOrder {
	my ($self, $order) = @_;
	if (ref $order ne 'ARRAY') {
		$self->{currentOrder} = [$order];
	} else {
		$self->{currentOrder} = $order;
	}
	return $self;
}

sub orderClause {
	my ($self, $order) = @_;
	my @list = @{ $order || $self->{currentOrder} || $self->{defaultOrder} };
	return @list ? 'ORDER BY '.join(',', @list) : '';
}

sub setPage {
	my ($self, $page, $size) = @_;
	$self->{limitOffset} = ($page - 1) * $size;
	$self->{limitAmount} = $size;
	return $self;
}

sub setLimit {
	my ($self, $size) = @_;
	$self->{limitOffset} = 0;
	$self->{limitAmount} = $size;
	return $self;
}

sub limitClause {
	my ($self, $value) = @_;
	unless ($value) {
		$value = "$self->{limitOffset}, $self->{limitAmount}"
			if $self->{limitOffset} =~ /^\d+$/ && $self->{limitAmount};
	}
	return $value ? "LIMIT $value" : '';
}

sub getAll {
	my ($self, $fields) = @_;
	my $sql   = $self->{dbPool}->getDb;
	my $what  = $self->chooseFields($fields) || 't.*';
	my $order = $self->orderClause;
	my $limit = $self->limitClause;
	return $sql->fetchArray($self->createSelectQuery($what, '1', $order, $limit));
}

sub getHash {
	my ($self, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return { map { +$_->{$key} => $_ } @{ $self->getAll($fields) } };
}

sub getAssocArray {
	my ($self, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return Eldhelm::Util::Tool->assocArray($self->getAll($fields), $key);
}

sub getAssocColumn {
	my ($self, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return Eldhelm::Util::Tool->assocColumn($self->getAll($fields), $key);
}

sub getListByIds {
	my ($self, $list, $fields) = @_;
	my $sql   = $self->{dbPool}->getDb;
	my $what  = $self->chooseFields($fields) || 't.*';
	my $order = $self->orderClause;
	return $sql->fetchArray(
		$self->createSelectQuery($what, '`'.$self->{pkFields}[0].'` IN ('.join(',', map { '?' } @$list).')', $order),
		@$list);
}

sub getHashByIds {
	my ($self, $list, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return { map { +$_->{$key} => $_ } @{ $self->getListByIds($list, $fields) } };
}

sub getById {
	my ($self, $id, $fields) = @_;
	return $self->getListByIds([$id], $fields)->[0] || {};
}

sub getFieldById {
	my ($self, $id, $field) = @_;
	my $row = $self->getById($id, [$field]);
	return $row->{$field};
}

sub getAssocArrayByIds {
	my ($self, $list, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return Eldhelm::Util::Tool->assocArray($self->getListByIds($list, $fields), $key);
}

sub createFilter {
	my ($self, $filter) = @_;
	my $compiled = Eldhelm::Database::Filter->new(filter => $filter)->compile;
	warn Dumper($compiled) if $self->{debug};
	return $compiled;
}

sub filter {
	my ($self, $filterData, $fields) = @_;
	my $sql    = $self->{dbPool}->getDb;
	my $what   = $self->chooseFields($fields) || 't.*';
	my $filter = $self->createFilter($filterData);
	my $order  = $self->orderClause;
	my $limit  = $self->limitClause;

	return $sql->fetchArray($self->createSelectQuery($what, $filter->{compiled}, $order, $limit), @{ $filter->{data} });
}

sub filterOne {
	my $self = shift;
	return $self->filter(@_)->[0];
}

sub filterHash {
	my ($self, $filter, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return { map { +$_->{$key} => $_ } @{ $self->filter($filter, $fields) } };
}

sub filterAssocArray {
	my ($self, $filter, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return Eldhelm::Util::Tool->assocArray($self->filter($filter, $fields), $key);
}

sub filterKeyValue {
	my ($self, $filter, $key, $fields) = @_;
	$key = $self->fieldList($fields, $key);
	return Eldhelm::Util::Tool->assocKeyValue($self->filter($filter, $fields), $key);
}

sub filterScalar {
	my ($self, $filter, $field) = @_;
	my $row = $self->filterOne($filter, [$field]);
	return unless $row;
	return $row->{$field};
}

sub save {
	my ($self, $data) = @_;
	my $sql = $self->{dbPool}->getDb;
	$sql->saveRow($self->{table}, $data, $self->{pkFields});
}

sub saveByFilter {
	my ($self, $data, $filter) = @_;
	my $sql = $self->{dbPool}->getDb;
	$sql->updateRow($self->{table}, $data, $filter);
}

sub saveArray {
	my ($self, $data) = @_;
	my $sql = $self->{dbPool}->getDb;
	foreach (@$data) {
		$sql->saveRow($self->{table}, $_, $self->{pkFields});
	}
}

sub remove {
	my ($self, $data) = @_;
	my $sql = $self->{dbPool}->getDb;
	$sql->deleteRow($self->{table}, $data);
}

sub removeByFilter {
	my ($self, $filterData, $fields) = @_;
	my $sql    = $self->{dbPool}->getDb;
	my $filter = $self->createFilter($filterData);
	my $limit  = $self->limitClause;

	return $sql->query($self->createDeleteQuery($filter->{compiled}, $limit), @{ $filter->{data} });
}

sub countAll {
	my ($self) = @_;
	my $sql = $self->{dbPool}->getDb;
	return $sql->fetchScalar("SELECT COUNT(*) FROM `$self->{table}`");
}

sub countByFilter {
	my ($self, $filterData) = @_;
	my $sql    = $self->{dbPool}->getDb;
	my $filter = $self->createFilter($filterData);
	return $sql->fetchScalar("SELECT COUNT(*) FROM `$self->{table}` WHERE $filter->{compiled}", @{ $filter->{data} });
}

1;
