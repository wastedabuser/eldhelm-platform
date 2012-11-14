package Eldhelm::Database::MySql;

use strict;
use DBI;
use DBD::mysql;
use Date::Format;
use Data::Dumper;
use Eldhelm::Util::Tool;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = {
		user    => $args{user},
		pass    => $args{pass},
		dbs     => $args{dbs},
		address => $args{address},
		port    => $args{port} || "3306",
	};
	bless $self, $class;

	$self->{host} = "dbi:mysql:$self->{dbs}:$self->{address}:$self->{port}";
	$self->connect;

	return $self;
}

sub connect {
	my ($self) = @_;
	my $state = $self->{dbh} = DBI->connect(
		$self->{host},
		$self->{user},
		$self->{pass},
		{   RaiseError => 1,
			PrintError => 0,
		}
	);
	$self->{dbh}->do("SET NAMES UTF8");
	return $state;
}

sub isConnected {
	my ($self) = @_;
	return $self->{dbh} && $self->{dbh}->ping ? 1 : undef;
}

sub dbh {
	my ($self) = @_;
	return $self->{dbh};
}

sub query {
	my ($self, $query, @params) = @_;
	my $sth = $self->{dbh}->prepare($query);
	for (my $i = 0 ; $i <= $#params ; $i++) {
		my $opts;
		if ($params[$i] =~ /^\d+\.?\d*$/) {
			$opts = { TYPE => DBI::SQL_NUMERIC };
		}
		$sth->bind_param($i + 1, $params[$i], $opts);
	}
	eval { $sth->execute(); };
	confess "$query: $@\n".Dumper(\@params) if $@;
	return $sth;
}

sub fetchScalar {
	my ($self, $query, @params) = @_;
	my $sth = $self->query($query, @params);
	my $data = $sth->fetchrow_arrayref;
	return $data ? $data->[0] : undef;
}

sub fetchRow {
	my ($self, $query, @params) = @_;
	my $sth = $self->query($query, @params);
	return $sth->fetchrow_hashref;
}

sub fetchArray {
	my ($self, $query, @params) = @_;
	my $sth = $self->query($query, @params);
	my @result;
	while (my $row = $sth->fetchrow_hashref) {
		push @result, $row;
	}
	return \@result;
}

sub fetchArrayOfArrays {
	my ($self, $query, @params) = @_;
	my $sth = $self->query($query, @params);
	return $sth->fetchall_arrayref;
}

sub fetchColumn {
	my ($self, $query, @params) = @_;
	my $sth = $self->query($query, @params);
	return $sth->fetchall_arrayref([0]) || [];
}

sub fetchHash {
	my ($self, $query, @params) = @_;
	my $key = pop @params;
	my $sth = $self->query($query, @params);
	my %result;
	while (my $row = $sth->fetchrow_hashref) {
		$result{ $row->{$key} } = $row;
	}
	return \%result;
}

sub fetchKeyValue {
	my ($self, $query, @params) = @_;
	my $value = pop @params;
	my $key   = pop @params;
	my $sth   = $self->query($query, @params);
	my %result;
	while (my $row = $sth->fetchrow_hashref) {
		$result{ $row->{$key} } = $row->{$value};
	}
	return \%result;
}

sub fetchAssocArray {
	my ($self, $query, @params) = @_;
	my $key = pop @params;
	my $data = $self->fetchArray($query, @params);
	return Eldhelm::Util::Tool->assocArray($data, $key);
}

sub fetchColumn {
	my ($self, $query, @params) = @_;
	my $sth = $self->query($query, @params);
	my @result;
	while (my @row = $sth->fetchrow_array) {
		push @result, $row[0];
	}
	return \@result;
}

sub desc {
	my ($self, $table) = @_;
	return $self->fetchArray("DESC `$table`");
}

sub descHash {
	my ($self, $table) = @_;
	if (!$self->{descCache}{$table}) {
		my $cols = $self->desc($table);
		$self->{descCache}{$table} = { map { +$_->{Field} => $_ } @$cols };
	}
	return $self->{descCache}{$table};
}

sub parseDate {
	my ($self, $str) = @_;
	if ($str =~ /^\d+$/) {
		return time2str("%Y-%m-%d %T", $str);
	}
	return $str;
}

sub prepareFields {
	my ($self, $table, $fields, $data) = @_;
	my $hcols = $self->descHash($table);
	my (@flds, $val);
	foreach (@$fields) {
		my $col = $hcols->{$_};
		if ($col->{Null} eq "YES" && $data->{$_} eq "") {
			$val = undef;
		} elsif ($col->{Type} eq "timestamp" && $col->{Default} eq "CURRENT_TIMESTAMP" && !$data->{$_}) {
			next;
		} elsif ($col->{Type} =~ /date|time/) {
			$val = $self->parseDate($data->{$_});
		} else {
			$val = $data->{$_};
		}
		push @flds, [ $_, $val ];
	}
	return @flds;
}

sub updateFields {
	my ($self, $table, $data) = @_;
	my $hcols = $self->descHash($table);
	my @fields = $self->prepareFields($table, [ grep { $_ ne "id" && $hcols->{$_} } keys %$data ], $data);
	return (join(",", map { "`$_->[0]`=?" } @fields), [ map { $_->[1] } @fields ]);
}

sub insertFields {
	my ($self, $table, $data) = @_;
	if (ref $data eq "ARRAY") {
		return unless $data->[0];
		my @fields = keys %{ $data->[0] };
		my %rows;
		foreach my $d (@$data) {
			push @{ $rows{ $_->[0] } }, $_->[1] foreach $self->prepareFields($table, \@fields, $d);
		}
		return (join(",", @fields), join(",", map { "?" } @fields), [ map { $rows{$_} } @fields ]);
	}
}

sub saveRow {
	my ($self, $table, $data, $pkFields) = @_;
	my ($fields, $values) = $self->updateFields($table, $data);
	my $hcols = $self->descHash($table);
	$pkFields ||= ["id"];
	my $pk = $pkFields->[0];
	my $query;
	if (@$pkFields > 1 || ($hcols->{$pk} && $hcols->{$pk}{Extra} !~ /auto_increment/)) {
		$query = "INSERT `$table` SET $fields ON DUPLICATE KEY UPDATE $fields";
		$self->query($query, @$values, @$values);
	} else {
		my $pkv = $data->{$pk};
		$query = ($pkv ? "UPDATE" : "INSERT")." `$table` SET $fields".($pkv ? " WHERE $pk = ?" : "");
		$self->query($query, @$values, $pkv || ());
		return $self->dbh->{mysql_insertid};
	}
	return;
}

sub updateRow {
	my ($self, $table, $data, $where) = @_;
	my (@filter, @fValues);
	my ($fields, $values) = $self->updateFields($table, $data);
	while (my ($k, $v) = each %$where) {
		push @filter,  "`$k`=?";
		push @fValues, $v;
	}
	my $query = "UPDATE `$table` SET $fields WHERE ".join(" AND ", @filter);
	$self->query($query, @$values, @fValues);
}

sub deleteRow {
	my ($self, $table, $where) = @_;
	my (@filter, @fValues);
	while (my ($k, $v) = each %$where) {
		push @filter,  "`$k`=?";
		push @fValues, $v;
	}
	my $query = "DELETE FROM `$table` WHERE ".join(" AND ", @filter);
	$self->query($query, @fValues);
}

sub insertArray {
	my ($self, $table, $data, $options) = @_;
	$options ||= {};
	my ($fields, $values, $valuesData) = $self->insertFields($table, $data);
	return unless $fields;

	my $query = ($options->{replace} ? "REPLACE" : "INSERT")." `$table` ($fields) VALUES ($values)";

	my $sth = $self->{dbh}->prepare($query);
	eval { $sth->execute_array({}, @$valuesData); };
	confess "$query: $@\n".Dumper($data) if $@;

	return $self->dbh->{mysql_insertid};
}

sub createInPlaceholder {
	my ($self, $field, $list) = @_;
	return "$field IN (".join(",", map { "?" } @$list).")";
}

1;
