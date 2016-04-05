package Eldhelm::Util::Tool;

=pod

=head1 NAME

Eldhelm::Util::Tool - A utility class for working with structures.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

use strict;
use Encode qw();
use Math::Random::MT qw(rand);
use Scalar::Util;

use Exporter 'import';
our @EXPORT_OK = qw(merge isIn isNotIn toList cloneStructure);

### UNIT TEST: 302_tool.pl ###

=item merge($ref, @list) Hash

Copies hashref key pairs from one or more hasref to other hasref. Returns the HashRef supplied via C<$ref>.

C<$ref> HashRef - The HashRef to be copied into
C<@list> Array - The list of Hashrefs to be copied.

=cut

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

=item isIn($val, @list) 1 or undef

Checks whether C<$val> exists into the C<@list>.

C<$val> String - Value to be searched for
C<@list> Array - The list to be searched in.

=cut

sub isIn {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($val, @values) = @_;
	foreach (@values) {
		return 1 if $_ eq $val;
	}
	return;
}

=item isIn($val, @list) 1 or undef

Same as C<isIn> but inverted.

C<$val> String - Value to be searched for
C<@list> Array - The list to be searched in.

=cut

sub isNotIn {
	return !isIn(@_);
}

=item toList($var) Array

The C<$var> could be a Scalar or an ArrayRef. The function will always return Array.

C<$var> Mixed - the valued to be represented as Array.

=cut

sub toList {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($var) = @_;
	return () unless defined $var;
	return ref $var eq "ARRAY" ? @$var : ($var);
}

=item arrayShuffle($array)

Suffles an ArrayRef in-place using Fisher Yates algorithm.

C<$array> ArrayRef - The list to be shuffled.

=cut

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

=item assocArray($array, $key) HashRef

Converts an ArrayRef containing HashRefs into HashRef.

C<$array> ArrayRef - The structure to be converted.
C<$key> ArrayRef or String - The property (or properties) to be used as key.

	Eldhelm::Util::Tool->assocArray([
		{ a => 1, b => 2 },
		{ a => 3, b => 4 },
		{ a => 1, b => 5 },
	], 'a');

Will return this:

	{
		'1' => [
			{ a => 1, b => 2 },
			{ a => 1, b => 5 },
		],
		'3'	=> [
			{ a => 3, b => 4 },
		],
	}

You can do this also:

	Eldhelm::Util::Tool->assocArray([
		{ a => 1, b => 2 },
		{ a => 3, b => 4 },
		{ a => 1, b => 5 },
	], ['a', 'b']);

Will return this:

	{
		'1' => {
			'2' => [
				{ a => 1, b => 2 },
			# ],
			'5' => [
				{ a => 1, b => 5 },
			# ],
		}
		'3' => {
			'4' => [
				{ a => 3, b => 4 },
			# ]
		}
	}

=cut

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

=item assocHash($array, $key) HashRef

Converts an ArrayRef containing HashRefs into HashRef.

C<$array> ArrayRef - The structure to be converted.
C<$key> ArrayRef or String - The property (or properties) to be used as key.

	Eldhelm::Util::Tool->assocHash([
		{ a => 1, b => 2 },
		{ a => 3, b => 4 },
		{ a => 1, b => 5 },
	], 'a');

Will return this:

	{
		'1' => { a => 1, b => 5 },
		'3' => { a => 3, b => 4 },
	}

You can do this also:

	Eldhelm::Util::Tool->assocHash([
		{ a => 1, b => 2 },
		{ a => 3, b => 4 },
		{ a => 1, b => 5 },
	], ['a', 'b']);

Will return this:

	{
		'1' => {
			'2' => { a => 1, b => 2 },
			'5' => { a => 1, b => 5 },
		}
		'3' => {
			'4' => { a => 3, b => 4 },
		}
	}

=cut

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

=item assocKeyValue($array, $key) HashRef

Converts an ArrayRef containing HashRefs into HashRef.

C<$array> ArrayRef - The structure to be converted.
C<$key> ArrayRef or String - The property (or properties) to be used as key.

	Eldhelm::Util::Tool->assocKeyValue([
		{ a => 1, b => 2, c => 6 },
		{ a => 3, b => 4, c => 7 },
		{ a => 1, b => 5, c => 8 },
	], ['a', 'b']);

Will return this:

	{
		'1' => 5,
		'3' => 4,
	}

You can do this also:
	
	Eldhelm::Util::Tool->assocKeyValue([
		{ a => 1, b => 2, c => 6 },
		{ a => 3, b => 4, c => 7 },
		{ a => 1, b => 5, c => 8 },
	], ['a', 'b', 'c']);

Will return this:

	{
		'1' => {
			'2' => 6,
			'5' => 8,
		}
		'3' => {
			'4' => 7,
		}
	}

=cut

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

=item assocColumn($array, $key) HashRef

Converts an ArrayRef containing HashRefs into HashRef.

C<$array> ArrayRef - The structure to be converted.
C<$key> ArrayRef or String - The property (or properties) to be used as key.

	Eldhelm::Util::Tool->assocColumn([
		{ a => 1, b => 2, c => 6 },
		{ a => 3, b => 4, c => 7 },
		{ a => 1, b => 5, c => 8 },
	], ['a', 'b']);

Will return this:

	{
		'1' => [2, 5],
		'3' => [4],
	}

You can do this also:

	Eldhelm::Util::Tool->assocColumn([
		{ a => 1, b => 2, c => 6 },
		{ a => 3, b => 4, c => 7 },
		{ a => 1, b => 5, c => 8 },
	], ['a', 'b', 'c']);

Will return this:

	{
		'1' => {
			'2' => [6],
			'5' => [8],
		}
		'3' => {
			'4' => [7],
		}
	}

=cut

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

=item jsonEncode($data) String

Encodes structure into JSON recursively. This is a simple function implemented in Perl.

C<$data> Mixed - The data to be encoded to JSON.

=cut

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

=item utfFlagDeep($data, $state) Mixed

Clones a structure recursively and applies C<Encode::_utf8_on> or C<Encode::_utf8_off> on every element in the structure.

C<$data> Mixed - The structure to be cloned.
C<$state> 1 or 0 or undef - Whether to use C<_utf8_on> or C<_utf8_off>.

=cut

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

=item cloneStructure($ref) Mixed

Clones a structure recursively.

C<$ref> Mixed - The structure to be cloned

=cut

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

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
