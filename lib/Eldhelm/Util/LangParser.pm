package Eldhelm::Util::LangParser;

=pod

=head1 NAME

Eldhelm::Util::LangParser - A special JSON parser.

=head1 SYNOPSIS

	my $a = Eldhelm::Util::LangParser->new(
		stream => '{"a":"value1"}'
	);
	my $b = Eldhelm::Util::LangParser->new(
		stream => '{"b":"value2"}'
	);
	my $c = $a->merge($b);

=head1 DESCRIPTION

A special JSON parser supporting node order and JavaScript comments.

This JSON parser is designed to compare and merge JSON files by preserving the nodes order.
It does this by merging based on a model.

It is called a Language Parser, because in Eldhelm Platform it is used to parse JSON files containing translations.

In general it is a complete JSON parser. It is for sure far slower than the JSON::XS alternative for general purpose tasks.

=head1 METHODS

=over

=cut

use strict;
use Data::Dumper;
use Carp;
use Encode qw();
use Eldhelm::Util::Tool;

sub ks             { "~" }
sub apr            { "a" }
sub opr            { "o" }
sub traverseNewRef { substr($_[0], 0, 1) eq apr() ? [] : {} }

sub traverseKey {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($parsed, $key, $value) = @_;

	my $ks     = ks;
	my $apr    = apr;
	my @chunks = split /$ks/, $key;
	my $ref    = $parsed ||= traverseNewRef($chunks[0]);
	do {
		my $k = shift @chunks;
		my $tp = substr $k, 0, 1;
		$k = substr $k, 1;

		if ($tp eq $apr) {
			foreach (0 .. $k) {
				$ref->[$_] = "" unless defined $ref->[$_];
			}
			if (@chunks) {
				$ref = $ref->[$k] ||= traverseNewRef($chunks[0]);
			} else {
				$ref->[$k] = $value;
			}
		} else {
			if (@chunks) {
				$ref = $ref->{$k} ||= traverseNewRef($chunks[0]);
			} else {
				$ref->{$k} = $value;
				delete $ref->{$k} unless $value;
			}
		}
	} while (@chunks);

	return $parsed;
}

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<path> String - Will parse a file;
C<stream> String - Will parse a stream;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {
		le  => "\n",
		ks  => Eldhelm::Util::LangParser::ks,
		apr => Eldhelm::Util::LangParser::apr,
		opr => Eldhelm::Util::LangParser::opr,
		%args
	};
	bless $self, $class;

	$self->readFile($args{path})     if $args{path};
	$self->readStream($args{stream}) if $args{stream};

	$self->parse if $self->{lines};
	$self->parseStruct($args{struct}) if $args{struct};

	return $self;
}

=item readStream($stream)

Loads a file into the object. Does not do any parsing.

C<$path> String - The path to file;

=cut

sub readFile {
	my ($self, $path) = @_;
	open FR, $path or confess $!;
	$self->{lines} = [ map { s/[\n\r]//g; $_ } <FR> ];
	$self->{lines}[0] =~ s/^\x{ef}\x{bb}\x{bf}//;
	if ($self->{utf8}) {
		Encode::_utf8_on($_) foreach @{ $self->{lines} };
	}
	close FR;
	return;
}

=item readStream($stream)

Loads a stream into the object. Does not do any parsing.

C<$stream> String - The content to be parsed;

=cut

sub readStream {
	my ($self, $stream) = @_;
	Encode::_utf8_on($stream) if $self->{utf8};
	$self->{lines} = [ split /(?:\r\n|\n\r|\n)/, $stream ];
	return;
}

=item parse()

Inititates the parsing of the loaded data.

=cut

sub parse {
	my ($self) = @_;
	$self->tokenize;
	$self->lex;
}

sub tokenize {
	my ($self, $stream) = @_;
	my ($buffer, $flag, $esc, $inlineCommentFlag);
	my $tokens = $self->{tokens} = [];
	my ($lnum, $cnum) = (0);
	foreach my $l (@{ $self->{lines} }) {
		$lnum++;
		if ($l =~ m|^[\s\t]*//(.*)$|) {
			push @$tokens, [ "comment", $1, $lnum, $cnum ];
			next;
		}
		my @chars = split //, $l;
		$cnum = 0;
		foreach (@chars) {
			$cnum++;
			if ($_ eq "\\" && !$esc) {
				$esc = 1;
				next;
			}
			if ($esc) {
				confess "Unexpected character escaped '$_' at line $lnum, character $cnum" if $_ !~ /[trn"\\]/;
				$buffer .= eval "'\\$_'";
				$esc = 0;
				next;
			}
			if ($flag && $_ ne '"') {
				confess "Control character 0x00-0x1f in string statement at line $lnum, character $cnum"
					if $self->checkForControlCharacters($_);
				$buffer .= $_;
				next;
			}
			if ($_ eq '"') {
				if (defined $buffer) {
					push @$tokens, [ "string", $buffer, $lnum, $cnum ];
					$buffer = undef;
				} else {
					$buffer = "";
				}
				$flag = !$flag;
				next;
			}
			if ($_ eq "/" && $chars[$cnum] eq "/") {
				$inlineCommentFlag = 1;
				last;
			}
			next if /[\s\t]/;
			if (/[\[\]]/) {
				push @$tokens, [ "array", $_, $lnum, $cnum ];
				next;
			}
			if (/[\{\}]/) {
				push @$tokens, [ "object", $_, $lnum, $cnum ];
				next;
			}
			if (/[:,]/) {
				push @$tokens, [ "symbol", $_, $lnum, $cnum ];
				next;
			}
			confess "Unexpected symbol '$_' in line '$l' at line $lnum, character $cnum";
		}
		if ($inlineCommentFlag && @$tokens) {
			$inlineCommentFlag = 0;
			my $lastTkn = $tokens->[-1][0] eq "symbol" ? $tokens->[-2] : $tokens->[-1];
			push @$lastTkn, join "", @chars[ $cnum + 1 .. $#chars ];
		}
	}
}

sub checkForControlCharacters {
	my ($self, $char) = @_;
	my $num = unpack('U0U*', $char);
	return $num <= 31;
}

sub lex {
	my ($self) = @_;
	my $data   = $self->{tokens};
	my $tkn    = shift @$data;
	$self->{syntax} = $self->lexToken($data, $tkn);
	if (@$data > 0) {
		$tkn = shift @$data;
		confess "Junk at line $tkn->[2], character $tkn->[3]";
	}
}

sub lexToken {
	my ($self, $data, $tkn) = @_;
	my $fn = "_lex_$tkn->[0]";
	if (!$self->can($fn)) {
		confess "Unexpected token $tkn->[0] at line $tkn->[2], character $tkn->[3]";
	}
	return $self->$fn($data, $tkn);
}

sub _lex_string {
	my ($self, $data, $tkn) = @_;
	return $tkn;
}

sub _lex_comment {
	my ($self, $data, $tkn) = @_;
	return $tkn;
}

sub _lex_array {
	my ($self,   $data) = @_;
	my (@syntax, $tkn)  = ("array");
	my $flag = 1;
	while ($tkn = shift @$data) {
		if ($tkn->[0] eq "comment") {
			push @syntax, $self->lexToken($data, $tkn);
			next;
		}
		if ($flag && $tkn->[0] eq "symbol") {
			confess "Unexpected symbol $tkn->[1] at line $tkn->[2], character $tkn->[3]";
		}
		my $close = $tkn->[0] eq "array" && $tkn->[1] eq "]";
		if ($flag && $close) {
			confess "Unexpected array close at line $tkn->[2], character $tkn->[3]";
		}
		last if $close;
		push @syntax, $self->lexToken($data, $tkn) if $flag;
		$flag = !$flag;
	}
	return \@syntax;
}

sub _lex_object {
	my ($self, $data) = @_;
	my %dmap;
	my (@syntax, $tkn, $key, $value) = ("object", \%dmap);
	my ($flag, $strFlag) = (1, 1);
	while ($tkn = shift @$data) {
		if ($tkn->[0] eq "comment") {
			push @syntax, $self->lexToken($data, $tkn);
			next;
		}
		if ($flag && $tkn->[0] eq "symbol") {
			confess "Unexpected symbol $tkn->[1] at line $tkn->[2], character $tkn->[3]";
		}
		my $close = $tkn->[0] eq "object" && $tkn->[1] eq "}";
		if ($flag && $close) {
			confess "Unexpected object close at line $tkn->[2], character $tkn->[3]";
		}
		if (defined $key && !defined $value && $close) {
			confess "Unexpected object close at line $tkn->[2], character $tkn->[3]";
		}
		last if $close;
		if ($strFlag && $flag && $tkn->[0] ne "string") {
			confess "Exepecting string but found $tkn->[0] at line $tkn->[2], character $tkn->[3]";
		}
		if ($flag) {
			if ($strFlag) {
				$key = $tkn->[1];
			} else {
				$value = $self->lexToken($data, $tkn);
			}
			$strFlag = !$strFlag;
		}
		if (defined $key && defined $value) {
			push @syntax, [ "pair", $key, $value ];
			$dmap{$key} = $value;
			$key        = undef;
			$value      = undef;
		}
		$flag = !$flag;
	}
	return \@syntax;
}

sub indent {
	my ($self, $level) = @_;
	return "\t" x $level;
}

=item deparse($callback) String

Converts the internal parsed structure to JSON stream.

C<$callback> FunctionRef - Optional; Applies the callback when compiling every node;

=cut

sub deparse {
	my ($self, $callback) = @_;
	$self->{characterCount} = 0;
	$self->{wordCount}      = 0;
	my @chunks = $self->deparseChunk($self->{syntax}, 0, $callback, "");
	$self->{stream} = $chunks[0];
	Encode::_utf8_off($self->{stream}) if $self->{utf8};
	return $self->{stream};
}

sub deparseChunk {
	my ($self, $chunk, $level, $callback, $key) = @_;
	return if !$chunk->[0];
	my $fn = "_deparse_$chunk->[0]";
	return $self->$fn($chunk, $level, $callback, $key);
}

sub _deparse_string {
	my ($self, $data, $level, $callback, $key) = @_;
	my $str = $data->[1];
	$str =~ s/\r//g;
	$str =~ s/\n/\\n/g;
	$self->{characterCount} += length $str;
	$self->{wordCount} += () = $str =~ m/\w+/g;
	$str = $callback->($self, $str, $key, $data->[4]) if $callback;
	return (qq~"$str"~, $data->[4] || ());
}

sub _deparse_comment {
	my ($self, $data, $level, $callback, $key) = @_;
	return (qq~//$data->[1]$self->{le}~);
}

sub deparseInlineComment {
	my ($self, $str) = @_;
	return qq~ //$str~;
}

sub _deparse_array {
	my ($self, $data, $level, $callback, $key) = @_;
	my @list = @$data[ 1 .. $#$data ];
	my $ret  = "[$self->{le}";
	my $i    = 0;
	foreach (@list) {
		my @chunks = $self->deparseChunk($_, $level + 1, $callback, ($key ? "$key~" : "")."$self->{apr}$i");
		$ret .= $self->indent($level + 1).$chunks[0];
		my $flag = $_->[0] ne "comment" && $i < @list - 1;
		$ret .= ","                                     if $flag;
		$ret .= $self->deparseInlineComment($chunks[1]) if $chunks[1];
		$ret .= $self->{le}                             if $flag;
		$i++;
	}
	$ret .= $self->{le}.$self->indent($level)."]";
	return ($ret);
}

sub _deparse_object {
	my ($self, $data, $level, $callback, $key) = @_;
	my @list = @$data[ 2 .. $#$data ];
	my $ret  = "{$self->{le}";
	my $i    = 0;
	foreach (@list) {
		my @chunks = $self->deparseChunk($_, $level + 1, $callback, $key);
		$ret .= $self->indent($level + 1).$chunks[0];
		my $flag = $_->[0] ne "comment" && $i < @list - 1;
		$ret .= ","                                     if $flag;
		$ret .= $self->deparseInlineComment($chunks[1]) if $chunks[1];
		$ret .= $self->{le}                             if $flag;
		$i++;
	}
	$ret .= $self->{le}.$self->indent($level)."}";
	return ($ret);
}

sub _deparse_pair {
	my ($self, $data, $level, $callback, $key) = @_;
	my @chunks = $self->deparseChunk($data->[2], $level, $callback, ($key ? "$key~" : "")."$self->{opr}$data->[1]");
	my $ch0 = shift @chunks;
	confess "Can not deparse a new line character in pair key: $data->[1]" if $data->[1] =~ /[\n\r]/;
	return (qq~"$data->[1]": $ch0~, @chunks);
}

=item deparseToFile($path)

Same as L<< $self->deparse >>, but writes the output to a file.

C<$path> String - Path to file;

=cut

sub deparseToFile {
	my ($self, $path) = @_;
	$self->deparse;
	$self->writeFile($path);
	return;
}

sub writeFile {
	my ($self, $path) = @_;
	confess "There is nothing to write to file" if !$self->{stream};
	open FW, ">$path" or confess "$!: $path";
	print FW $self->{stream};
	close FW;
	return;
}

=item compare($parser) Eldhelm::Util::LangParser

Compares the parsed structure inside to another C<Eldhelm::Util::LangParser> and returns a new C<Eldhelm::Util::LangParser> containing the diferences.

C<$parser> Eldhelm::Util::LangParser - The structure to be compared with;

=cut

sub compare {
	my ($self, $parser) = @_;
	my $diff = $self->compareSubset($self->{syntax}[2], $parser->{syntax}[2]);
	return Eldhelm::Util::LangParser->new(syntax => $diff);
}

sub compareSubset {
	my ($self, $set1, $set2) = @_;
	confess "Can not compare $set1->[0] with $set2->[0] near:\nSet1:\n".Dumper($set1->[1])."\nSet2\n".Dumper($set2->[1])
		if $set1->[0] ne $set2->[0];
	my $fn = "_compare_$set1->[0]";
	return $self->$fn($set1, $set2);
}

sub _compare_array {
	my ($self, $set1, $set2) = @_;
	my @list  = @$set1[ 1 .. $#$set1 ];
	my @list2 = @$set2[ 1 .. $#$set2 ];
	my $i     = 0;
	my @diff;
	my $isDf = @list == @list2;
	foreach (@list) {
		if (!$isDf) {
			if (!$list2[$i]) {
				push @diff, $_;
				next;
			}
			push @diff, $list2[$i];
		}
		if ($_->[0] =~ /array|object|string/) {
			my $df = $self->compareSubset($_, $list2[$i]);
			push @diff, $df if @$df;
		}
		$i++;
	}
	unshift @diff, "array" if @diff;
	return \@diff;
}

sub _compare_object {
	my ($self, $set1, $set2) = @_;
	my @list = @$set1[ 2 .. $#$set1 ];
	my %data = %{ $set2->[1] };
	my @diff;
	foreach (@list) {
		next if $_->[0] ne "pair";
		if (!$data{ $_->[1] }) {
			push @diff, $_;
			next;
		}
		if ($_->[2][0] =~ /array|object|string/) {
			my $df = $self->compareSubset($_->[2], $data{ $_->[1] });
			push @diff, [ "pair", $_->[1], $df ] if @$df;
		}
	}
	unshift @diff, "object", { map { +$_->[1] => $_->[2] } @diff } if @diff;
	return \@diff;
}

sub _compare_string {
	my ($self, $str1, $str2) = @_;

	return [];
}

=item mergeDiff($set)

Merges another C<Eldhelm::Util::LangParser> deeply directly into the parsed structure inside.

C<$set> Eldhelm::Util::LangParser - The structure to be merged;

=cut 

sub merge {
	my ($self, $set) = @_;
	$self->mergeSubset(Eldhelm::Util::Tool->cloneStructure($self->{syntax}), $self->{syntax}, $set->{syntax});
	return;
}

=item mergeDiff($model, $diffSet)

Merges the contents of C<$diffSet> deeply to the parsed structure inside, based on the C<$model>

C<$model> Eldhelm::Util::LangParser - The structure acting as a model;
C<$diffSet> Eldhelm::Util::LangParser - The structure to be merged;

=cut

sub mergeDiff {
	my ($self, $model, $diffSet) = @_;
	$self->mergeSubset($model->{syntax}[2], $self->{syntax}[2], $diffSet->{syntax});
	return;
}

sub mergeSubset {
	my ($self, $model, $set1, $set2) = @_;
	my $message = "Can not merge $set1->[0]($set1->[1]) with $set2->[0]($set2->[1]). Maybe you are merging a diff with a full translation.";
	confess "$message: 
============= first =============
".Dumper($set1->[1])." 
============= second ============
".Dumper($set2->[1])."
=============  end  =============
$message"
		if $set1->[0] ne $set2->[0];

	my $fn = "_merge_$model->[0]";
	return $self->$fn($model, $set1, $set2);
}

sub _merge_array {
	my ($self, $model, $set1, $set2) = @_;
	my $ln = $#$model;
	for (my $i = 1 ; $i <= $ln ; $i++) {
		my $bas = $set1->[$i];
		my $ovr = $set2->[$i];
		if ($bas && $ovr && $bas->[0] =~ /array|object/ && $bas->[0] eq $ovr->[0]) {
			$self->mergeSubset($model->[$i], $bas, $ovr);

		} elsif ($ovr && $ovr->[0] eq "string") {
			$set1->[$i] = $ovr if $ovr->[1];

		} elsif ($ovr) {
			$set1->[$i] = $ovr;
		}
	}
}

sub _merge_object {
	my ($self, $model, $set1, $set2) = @_;
	my @list = @$model[ 2 .. $#$model ];
	my $base = $set1->[1];
	my $data = $set2->[1];
	my $i    = @$set1 <= @$model ? 1 : @$set1;
	foreach (@list) {
		$i++;
		next if $_->[0] ne "pair";
		my $key   = $_->[1];
		my $mNode = $data->{$key};
		if ($mNode && !$base->{$key}) {
			$base->{$key} = $mNode;
			splice @$set1, $i, 0, [ "pair", $key, $mNode ];

		} elsif ($mNode && $_->[2][0] =~ /array|object/) {
			$self->mergeSubset($_->[2], $base->{$key}, $mNode);

		} elsif ($mNode && $base->{$key}) {

			$base->{$key} = $mNode;
			my $replaceIndex;
			if ($key ne $set1->[$i][1]) {
				$self->outputWarning(
					"Indexing position missmatch: $key <=> $set1->[$i][1] at position $i. Will search for item...");
				$replaceIndex = 0;
				foreach my $si (@$set1) {
					last if ref $si eq "ARRAY" && $si->[1] eq $key;
					$replaceIndex++;
				}
				$self->outputWarning("$key found at position $replaceIndex");
			} else {
				$replaceIndex = $i;
			}
			splice @$set1, $replaceIndex, 1, [ "pair", $key, $mNode ];
		}
	}
}

sub parseStruct {
	my ($self, $ref) = @_;
	$self->{syntax} = $self->parseRef($ref);
}

sub parseRef {
	my ($self, $ref) = @_;
	if (ref $ref eq "ARRAY") {
		return $self->parseArrayRef($ref);
	} elsif (ref $ref eq "HASH") {
		return $self->parseHashRef($ref);
	} elsif (!ref) {
		return $self->parseString($ref);
	}
}

sub parseArrayRef {
	my ($self, $ref) = @_;
	return [ "array", map { $self->parseRef($_) } @$ref ];
}

sub parseHashRef {
	my ($self, $ref) = @_;
	my %dmap;
	my @syntax = ("object", \%dmap);
	foreach my $key (keys %$ref) {
		my $value = $self->parseRef($ref->{$key});
		push @syntax, [ "pair", $key, $value ];
		$dmap{$key} = $value;
	}
	return \@syntax;
}

sub parseString {
	my ($self, $ref) = @_;
	$ref =~ s/(["])/\\$1/g;
	return [ "string", $ref ];
}

sub getStrokes {
	my ($self) = @_;
	my @strokes;
	$self->deparse(
		sub {
			my ($self, $str, $key) = @_;
			my $value = $str;
			Encode::_utf8_off($value) if $self->{utf8};
			$value =~ s/\\"/"/g;
			push @strokes,
				{
				key   => $key,
				value => $value,
				};
			return $str;
		}
	);
	return \@strokes;
}

sub outputWarning {
	my ($self, $str) = @_;
	warn $str;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
