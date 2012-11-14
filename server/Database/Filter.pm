package Eldhelm::Database::Filter;

use strict;

sub new {
	my ($class, %args) = @_;
	my $self = {
		filter => $args{filter},
		fn     => { or => "OR" }
	};
	bless $self, $class;

	return $self;
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
	while (my ($k, $v) = each %$filter) {
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
	return [ join(" AND ", @where), \@data ];
}

sub compileArrayRef {
	my ($self, $filter) = @_;
	my @list = @$filter;
	my $nm   = shift @list;
	my ($compiled, @chunks, @data);
	foreach (@list) {
		my $fl = $self->compileRef($_);
		push @chunks, $fl->[0];
		push @data,   @{ $fl->[1] };
	}
	my $fn = $self->{fn}{$nm};
	if ($fn) {
		$compiled = join(" $fn ", @chunks);
	}
	return [ $compiled, \@data ];
}

1;
