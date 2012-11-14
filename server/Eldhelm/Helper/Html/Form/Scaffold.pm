package Eldhelm::Helper::Html::Form::Scaffold;

use strict;
use Data::Dumper;

use base qw(Eldhelm::Helper::Html::Form);

sub new {
	my ($class, %args) = @_;
	my $self = Eldhelm::Helper::Html::Form->new(%args);
	bless $self, $class;

	$self->{formLists} = $args{formLists};
	$self->{table}     = $args{table};
	$self->{dbPool}    = Eldhelm::Database::Pool->new;
	$self->{skip}      = $args{skip} || [];
	$self->{skipMap}   = { map { +$_ => 1 } @{ $self->{skip} } };

	$self->createFields;

	return $self;
}

sub createFields {
	my ($self) = @_;

	my $dbh = $self->{dbPool}->getDbh;

	my $sth = $dbh->column_info(undef, $self->{dbPool}{dbs}, $self->{table}, "%");
	my $list = $sth->fetchall_arrayref({});

	my $sth = $dbh->foreign_key_info(undef, undef, undef, undef, $self->{dbPool}{dbs}, $self->{table});
	my $allKeys = $sth->fetchall_arrayref({});
	my %fks;
	foreach (grep { $_->{PKTABLE_NAME} } @$allKeys) {
		$fks{ $_->{FKCOLUMN_NAME} } = $_;
	}

	my $field;
	foreach (sort { $a->{ORDINAL_POSITION} <=> $b->{ORDINAL_POSITION} } @$list) {
		(my $lbl = ucfirst $_->{COLUMN_NAME}) =~ s/_+(.)/" ".uc($1)/ge;
		my $fk = $fks{ $_->{COLUMN_NAME} };

		next if $self->{skipMap}{ $_->{COLUMN_NAME} };

		if ($_->{COLUMN_NAME} eq "id") {
			$field = $self->createHidden(
				{   id   => $_->{COLUMN_NAME},
					name => $_->{COLUMN_NAME},
				}
			);
		} elsif ($fk && $fk->{PKTABLE_NAME}) {
			$field = $self->createCombo(
				{   id    => $_->{COLUMN_NAME},
					name  => $_->{COLUMN_NAME},
					label => $lbl,
				},
				$self->createRelationList($_->{COLUMN_NAME}, $fk->{PKTABLE_NAME}, $_->{IS_NULLABLE} eq "YES")
			);
		} elsif ($_->{TYPE_NAME} =~ /tinyint/i && $_->{COLUMN_SIZE} == 1) {
			$field = $self->createCheckbox(
				{   id    => $_->{COLUMN_NAME},
					name  => $_->{COLUMN_NAME},
					label => $lbl,
				}
			);
		} elsif ($_->{TYPE_NAME} =~ /text/i) {
			$field = $self->createArea(
				{   id    => $_->{COLUMN_NAME},
					name  => $_->{COLUMN_NAME},
					label => $lbl,
				}
			);
		} elsif ($_->{TYPE_NAME} =~ /enum/i) {
			$field = $self->createCombo(
				{   id    => $_->{COLUMN_NAME},
					name  => $_->{COLUMN_NAME},
					label => $lbl,
				},
				[   $_->{IS_NULLABLE} eq "YES" ? { value => "- none -" } : (),
					map ({ key => $_, value => $_ }, @{ $_->{mysql_values} })
				],
			);
		} else {
			$field = $self->createText(
				{   id    => $_->{COLUMN_NAME},
					name  => $_->{COLUMN_NAME},
					label => $lbl,
				}
			);
		}
		$self->add($field);
	}
	$self->add($self->createSubmit({ value => "Save" }));
}

sub createRelationList {
	my ($self, $field, $table, $nullable) = @_;
	my ($k, $v) = qw(id name);
	if ($self->{formLists} && $self->{formLists}{$field}) {
		my $ref = $self->{formLists}{$field};
		$k = $ref->{key}   if $ref->{key};
		$v = $ref->{value} if $ref->{value};
	}
	return [
		$nullable ? { value => "- none -" } : (),
		$table ? @{ $self->{dbPool}->getDb->fetchArray("SELECT $k as `key`, $v as `value` FROM `$table`") } : (),
	];
}

1;
