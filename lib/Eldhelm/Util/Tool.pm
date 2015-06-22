package Eldhelm::Util::Tool;

use strict;
use Encode qw();
use Math::Random::MT qw(rand);
use Scalar::Util;

use base qw(Exporter);
our @EXPORT_OK = qw(merge isIn isNotIn toList);

### UNIT TEST: 302_tool.pl ###

sub merge {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref, @list) = @_;
	foreach my $r (@list) {
		if (ref $r eq "HASH") {
			$ref->{$_} = $r->{$_} foreach keys %$r;
		}
	}
	return $ref;
}

sub isIn {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($val, @values) = @_;
	foreach (@values) {
		return 1 if $_ eq $val;
	}
	return;
}

sub isNotIn {
	return !isIn(@_);
}

sub toList {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($var) = @_;
	return () unless defined $var;
	return ref $var eq "ARRAY" ? @$var : ($var);
}

# fisher_yates_shuffle
sub arrayShuffle {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($array) = @_;
	return if !@$array;
	my $i;
	for ($i = @$array ; --$i ;) {
		my $j = int rand($i + 1);
		next if $i == $j;
		@$array[ $i, $j ] = @$array[ $j, $i ];
	}
}

sub assocArray {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($array, $key) = @_;
	my @keys = ref $key eq "ARRAY" ? @$key : ($key);
	my $lk = pop @keys;
	return {} unless $lk;
	my %result;
	foreach my $it (@$array) {
		my $ret = \%result;
		$ret = $ret->{ $it->{$_} } ||= {} foreach @keys;
		push @{ $ret->{ $it->{$lk} } }, $it;
	}
	return \%result;
}

sub assocHash {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($array, $key) = @_;
	my @keys = ref $key eq "ARRAY" ? @$key : ($key);
	my $lk = pop @keys;
	return {} unless $lk;
	my %result;
	foreach my $it (@$array) {
		my $ret = \%result;
		$ret = $ret->{ $it->{$_} } ||= {} foreach @keys;
		$ret->{ $it->{$lk} } = $it;
	}
	return \%result;
}

sub assocKeyValue {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($array, $key) = @_;
	my @keys = ref $key eq "ARRAY" ? @$key : ($key);
	return {} if @keys < 2;
	my $vKey = pop @keys;
	my $lk   = pop @keys;
	my %result;
	foreach my $it (@$array) {
		my $ret = \%result;
		$ret = $ret->{ $it->{$_} } ||= {} foreach @keys;
		$ret->{ $it->{$lk} } = $it->{$vKey};
	}
	return \%result;
}

sub assocColumn {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($array, $key) = @_;
	my @keys = ref $key eq "ARRAY" ? @$key : ($key);
	return {} if @keys < 2;
	my $vKey = pop @keys;
	my $lk   = pop @keys;
	my %result;
	foreach my $it (@$array) {
		my $ret = \%result;
		$ret = $ret->{ $it->{$_} } ||= {} foreach @keys;
		push @{ $ret->{ $it->{$lk} } }, $it->{$vKey};
	}
	return \%result;
}

sub mapArray {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($array, $key) = @_;
	my @keys = ref $key eq "ARRAY" ? @$key : ($key);
	my $lk = pop @keys;
	my %result;
	foreach my $it (@$array) {
		my $ret = \%result;
		$ret = $ret->{ $it->{$_} } ||= {} foreach @keys;
		$ret->{ $it->{$lk} } = $it;
	}
	return \%result;
}

sub jsonEncode {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;

	if (ref $data eq "ARRAY") {
		return "[".join(",", map { jsonEncode($_) } @$data)."]";
	} elsif (ref $data eq "HASH") {
		return "{".join(",", map { '"'.$_.'":'.jsonEncode($data->{$_}) } keys %$data)."}";
	} elsif (!defined $data) {
		return "null";
	} elsif ($data eq "true" || $data eq "false" || Scalar::Util::looks_like_number($data)) {
		return $data;
	} else {
		$data =~ s/\\/\\\\/g;
		$data =~ s/\//\\\//g;
		$data =~ s/"/\\"/g;
		$data =~ s/\n/\\n/g;
		$data =~ s/\r/\\r/g;
		$data =~ s/\t/\\t/g;
		$data =~ s/\f/\\f/g;
		$data =~ s/[\b]/\\b/g;
		return '"'.$data.'"';
	}
}

sub utfFlagDeep {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data, $state) = @_;
	return if !defined $data;

	my $ret;
	if (ref $data eq "ARRAY") {
		$ret = [];
		push @$ret, utfFlagDeep($_, $state) foreach @$data;
	} elsif (ref $data eq "HASH") {
		$ret = {};
		$ret->{$_} = utfFlagDeep($data->{$_}, $state) foreach keys %$data;
	} elsif (ref $data eq "JSON::XS::Boolean") {
		return int($data);
	} elsif (Scalar::Util::looks_like_number($data)) {
		return $data * 1;
	} else {
		$ret = "$data";
		if ($state) {
			Encode::_utf8_on($ret);
		} else {
			Encode::_utf8_off($ret);
		}
	}
	return $ret;
}

sub cloneStructure {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref) = @_;
	my $nRef;
	if (Scalar::Util::reftype($ref) eq 'ARRAY') {
		$nRef = [ map { cloneStructure($_) } @$ref ];
	} elsif (Scalar::Util::reftype($ref) eq 'HASH') {
		$nRef = { map { +$_ => cloneStructure($ref->{$_}) } keys %$ref };
	} elsif (!ref $ref) {
		$nRef = $ref;
	}
	return $nRef;
}

1;
