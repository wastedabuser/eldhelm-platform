package Eldhelm::Database::Filter;

use strict;

sub new {
	my ($class, %args) = @_;
	my $self = {
		filter => $args{filter},
		op     => {
			or   => "OR",
			'||' => "OR",
			and  => "AND",
			'&&' => "AND",
		},
		fn => {
			'='  => "=",
			eq   => "=",
			'>'  => ">",
			gt   => ">",
			'<'  => "<",
			lte  => "<",
			'>=' => ">=",
			gte  => ">=",
			'<=' => "<=",
			lt   => "<=",
			'!=' => "!=",
			ne   => "!=",
		}
	};
	bless $self, $class;

	return $self;
}

sub compileVar {
	my ($self, $nm) = @_;
	$nm =~ s/[^a-z0-9_]//ig;
	return $nm;
}

sub compile {
	my ($self) = @_;
	my $fl = $self->compileRef($self->{filter});
	($self->{compiled}, $self->{data}) = @$fl;
	$self->{compiled} ||= 1;
	return $self;
}

sub compileRef {
	my ($self, $filter) = @_;
	if (ref $filter eq "HASH") {
		return $self->compileHashRef($filter);
	} elsif (ref $filter eq "ARRAY") {
		return $self->compileArrayRef($filter);
	}
	return [ "1", [] ];
}

sub compileHashRef {
	my ($self, $filter) = @_;
	my (@where, @data);
	foreach (keys %$filter) {
		my $k = $self->compileVar($_);
		my $v = $filter->{$_};
		if (ref $v eq "ARRAY") {
			push @where, "`$k` IN (".join(",", map { "?" } @$v).")";
			push @data, @$v;
		} elsif ($v =~ /^null$/i) {
			push @where, "`$k` IS NULL";
		} elsif (defined $v) {
			push @where, "`$k` = ?";
			push @data,  $v;
		}
	}
	return [ join(" AND ", @where) || "1", \@data ];
}

sub compileArrayRef {
	my ($self, $filter) = @_;
	my @list = @$filter;
	my $nm   = shift @list;
	my ($compiled, @chunks, @data);
	my $op = $self->{op}{$nm};
	if ($op) {
		foreach (@list) {
			my $fl = $self->compileRef($_);
			push @chunks, $fl->[0];
			push @data, @{ $fl->[1] } if ref $fl->[1] eq "ARRAY";
		}
		return [ "(".join(" $op ", @chunks).")", \@data ],;
	}
	my $fn = $self->{fn}{$nm};
	if ($fn) {
		my $var = $self->compileVar(shift @list);
		return [ "`$var` $fn ?", \@list ];
	}
	my $method = "_fn_$nm";
	return $self->$method(@list) if $self->can($method);
	return [ "1", [] ];
}

sub _fn_like {
	my ($self, $var, $value) = @_;
	$var = $self->compileVar($var);
	return [ "`$var` LIKE ?", ["%$value%"] ];
}

sub _fn_isnull {
	my ($self, $var, $value) = @_;
	$var = $self->compileVar($var);
	return ["`$var` IS NULL"];
}

sub _fn_between {
	my ($self, $var, $value1, $value2) = @_;
	$var = $self->compileVar($var);
	return [ "`$var` BETWEEN ? AND ?", [ $value1, $value2 ] ];
}

sub _fn_streq {
	my ($self, $var, $value) = @_;
	$var = $self->compileVar($var);
	return [ "STRCMP(`$var`, ?) = 0", [$value] ];
}

1;
