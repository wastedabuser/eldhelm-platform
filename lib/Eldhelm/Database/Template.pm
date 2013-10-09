package Eldhelm::Database::Template;

use strict;
use Carp;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = {
		placeholders       => {},
		filterPlaceholders => {},
		conditions         => {},
		fields             => {},
		format             => {},
		tableAliases       => {},
		%args,
	};
	bless $self, $class;

	$self->init(\%args);

	return $self;
}

sub getSql {
	my ($self) = @_;
	return $self->{sql};
}

sub getPath {
	my ($self, $name) = @_;
	return "$self->{rootPath}Eldhelm/Application/Template/".join("/", split(/\./, $name)).".tsql";
}

sub descTable {
	my ($self, $table) = @_;
	my $sql = $self->getSql;
	confess "No sql" unless $sql;
	return $self->{tableDesc}{$table} ||= $sql->fetchArray("DESC $table");
}

sub descTableAsHash {
	my ($self, $table) = @_;
	return $self->{tableDescHash}{$table} ||= { map { +$_->{Field} => $_ } @{ $self->descTable($table) } };
}

sub init {
	my ($self, $args) = @_;
	foreach (qw(file stream placeholders filter)) {
		next unless $args->{$_};
		$self->$_($args->{$_});
	}
}

sub find_path {
	my ($self, $path) = @_;
	my $pt = $self->getPath($path);
	confess "Can not find file: $pt" unless $pt;

	$path =~ s|/([^/]+)$||;
	$self->{file_name} = $1;
	$self->{path}      = $path;

	return $pt;
}

sub load_file {
	my ($self, $path) = @_;
	$path = $self->find_path($path);
	open FR, $path or confess "Can not load path: $path; $!";
	$self->{stream} = join "\n", <FR>;
	close FR;
	return;
}

sub load_stream {
	my ($self, $stream) = @_;
	$self->{stream} = $stream;
	return;
}

sub file {
	my ($self, $path) = @_;
	$self->load_file($path);
	$self->analyze;
	return $self;
}

sub stream {
	my ($self, $str) = @_;
	$self->load_stream($str);
	$self->analyze;
	return $self;
}

sub parse {
	my ($self) = @_;
	return if !$self->{stream};

	$self->applyPlaceholders;

	$self->{syntax} = $self->lex($self->tokenize($self->{stream}));

	foreach my $k (keys %{ $self->{append} }) {
		my @list;
		foreach (@{ $self->{append}{$k} }) {
			my ($flds) = $self->lexTokenByName($k, undef, $self->tokenize($_));
			push @list, @$flds;
		}
		$self->{"append_tokens_$k"} = \@list;
	}

	return;
}

sub analyze {
	my ($self) = @_;

	my $placeholders = $self->{placeholders} = { $self->{stream} =~ m/\{(\w+)[\s\n\r\t]*(.*?)[\s\n\r\t]*\}/gs };

	my @pvals = $self->{stream} =~ m/\{(append)\s*(\w+)[\s\n\r\t]*(.*?)[\s\n\r\t]*\}/gs;
	for (my $i = 0 ; $i <= $#pvals ; $i += 3) {
		push @{ $self->{ $pvals[$i] }{ $pvals[ $i + 1 ] } }, $pvals[ $i + 2 ];
	}
	$self->{stream} =~ s/\{(\w+).*?\}/{$1}/gs;

	$self->{filterPlaceholders} = { $self->{stream} =~ m/\[(\w+)[\s\n\r\t]*(.*?)[\s\n\r\t]*\]/gs };
	$self->{stream} =~ s/\[(\w+).*?\]/[$1]/gs;

	$self->extend(join "/", $self->{path} || (), $placeholders->{extends})
		if $placeholders->{extends};

	return;
}

sub applyPlaceholders {
	my ($self) = @_;
	$self->{stream} =~ s/\{(.+?)\}/$self->{placeholders}{$1}/ge;
	return;
}

sub tokenize {
	my ($self, $stream) = @_;
	my ($buf, $bufW, $bufN, $bufI, $bufOp, $flag, $esc);
	my @tokens;
	my @lines = split /[\n\r]+/, $stream;
	my ($lnum, $cnum) = (0);
	foreach my $l (@lines) {
		$lnum++;
		if ($l =~ m|^[\s\t]*--(.*)$|) {
			push @tokens, [ "comment", $1, $lnum, $cnum ];
			next;
		}
		my @chars = split //, $l;
		$cnum = 0;
		foreach (@chars, "") {
			$cnum++;
			if ($_ eq "\\" && !$esc) {
				$esc = 1;
				next;
			}
			if ($esc) {
				$buf .= eval "'\\$_'";
				$esc = 0;
				next;
			}
			if ($flag && $_ ne "'") {
				$buf .= $_;
				next;
			}

			if ($_ eq "'") {
				if (defined $buf) {
					push @tokens, [ "string", $buf, $lnum, $cnum ];
					$buf = undef;
				} else {
					$buf = "";
				}
				$flag = !$flag;
				next;
			}

			if (/[\d\.\-]/ && !$bufW && !$bufI) {
				$bufN .= $_;
				next;
			} elsif (defined $bufN) {
				my $tp;
				$tp = "symbol"   if $bufN eq ".";
				$tp = "operator" if $bufN eq "-";
				push @tokens, [ $tp || "number", $bufN, $lnum, $cnum ];
				$bufN = undef;
			}

			if (/[\+\*\/<>=!]/) {
				$bufOp .= $_;
				next;
			} elsif (defined $bufOp) {
				push @tokens, [ "operator", $bufOp, $lnum, $cnum ];
				$bufOp = undef;
				redo;
			}

			if (/[\w`]/ && !$bufN && !$bufI) {
				$bufW .= $_;
				next;
			} elsif (defined $bufW) {
				my $tp = "word";
				$tp = "function" if $_ eq "(";
				push @tokens, [ $tp, $bufW, $lnum, $cnum ];
				$bufW = undef;
				redo;
			}

			if (/[\{\}\[\]\w]/ && !$bufN && !$bufW) {
				$bufI .= $_;
				next;
			} elsif (defined $bufI) {
				push @tokens, [ "instruction", $bufI, $lnum, $cnum ];
				$bufI = undef;
				redo;
			}

			if (/[\(\)]/) {
				push @tokens, [ ($_ eq "(" ? "open" : "close")."Bracket", $_, $lnum, $cnum ];
				next;
			}
			if (/[,\?]/) {
				push @tokens, [ "symbol", $_, $lnum, $cnum ];
				next;
			}

		}
	}
	return \@tokens;
}

sub lex {
	my ($self, $tokens) = @_;
	my $tkn = shift @$tokens;
	return $self->lexToken($tkn, $tokens);
}

sub lexToken {
	my ($self, $tkn, $tokens) = @_;
	if ($tkn->[0] eq "word") {
		return $self->lexTokenByName(lc($tkn->[1]), $tkn, $tokens);
	}
}

sub lexTokenByName {
	my ($self, $name, $tkn, $tokens) = @_;
	my $fn = "_lex_$name";
	if (!$self->can($fn)) {
		confess "Unexpected token $tkn->[0] '$tkn->[1]' at line $tkn->[2], character $tkn->[3]" if $tkn;
		confess "Can not lex token $name. No handler function $fn.";
	}
	return $self->$fn($tkn, $tokens);
}

sub _lex_select {
	my ($self, $tkn, $tokens) = @_;
	my (@syntax, $flds, $chunks, @grp, @ordr, @lmt, $tkn) = ("select");
	my $lv = 0;

	($flds, $tkn) = $self->_lex_fields($tkn, $tokens, 1);
	push @syntax, $flds;

	if ($tkn->[1] =~ /from/i) {
		($chunks, $tkn) = $self->_lex_tables($tkn, $tokens, 1);
		push @syntax, $chunks;
	}
	if ($tkn->[1] =~ /where/i) {
		($chunks, $tkn) = $self->_lex_conditions($tkn, $tokens, 1);
		push @syntax, $chunks;
	}
	if ($tkn->[1] =~ /group/i) {
		push @grp,    "group";
		push @syntax, \@grp;
		while ($tkn = shift @$tokens) {
			$lv++ if $tkn->[0] eq "openBracket";
			$lv-- if $tkn->[0] eq "closeBracket";
			last if $lv == 0 && $tkn->[0] eq "word" && $tkn->[1] =~ /having|order|limit/i;
			my $expr = $self->lexExpression($tkn, $tokens);

			# $lv++ if $expr->[0] eq "function";
			push @grp, $expr;
		}
	}
	if ($tkn->[1] =~ /having/i) {
		($chunks, $tkn) = $self->_lex_havingConditions($tkn, $tokens, 1);
		push @syntax, $chunks;
	}
	if ($tkn->[1] =~ /order/i) {
		push @ordr,   "order";
		push @syntax, \@ordr;
		while ($tkn = shift @$tokens) {
			$lv++ if $tkn->[0] eq "openBracket";
			$lv-- if $tkn->[0] eq "closeBracket";
			last if $lv == 0 && $tkn->[0] eq "word" && $tkn->[1] =~ /limit/i;
			my $expr = $self->lexExpression($tkn, $tokens);

			# $lv++ if $expr->[0] eq "function";
			push @ordr, $expr;
		}
	}
	if ($tkn->[1] =~ /limit/i) {
		push @lmt,    "limit";
		push @syntax, \@lmt;
		while ($tkn = shift @$tokens) {
			$lv++ if $tkn->[0] eq "openBracket";
			$lv-- if $tkn->[0] eq "closeBracket";
			push @lmt, $tkn;
		}
	}
	return \@syntax;
}

sub _lex_fields {
	my ($self, $tkn, $tokens, $nodeName) = @_;
	my (@flds, $lv, $flag);
	push @flds, "fields" if $nodeName;
	while (1) {
		my @field = ("field", undef);
		while ($tkn = shift @$tokens) {
			$lv++ if $tkn->[0] eq "openBracket";
			$lv-- if $tkn->[0] eq "closeBracket";
			if (   $lv == 0
				&& $tkn->[0] eq "word"
				&& $tokens->[0]
				&& $tokens->[0][0] ne "openBracket"
				&& $tokens->[1]
				&& $tokens->[1][1] eq "*")
			{
				$field[1] = "*";
				$field[2] = $tkn->[1];
				shift(@$tokens);
				last unless $tkn = shift(@$tokens);
			}
			if ($lv == 0 && $tkn->[0] eq "word" && lc($tkn->[1]) eq "as") {
				$tkn = shift(@$tokens);
				$field[1] = $tkn->[1];
				last unless $tkn = shift(@$tokens);
			}
			last if $lv == 0 && $tkn->[0] eq "symbol" && $tkn->[1] eq ",";
			if ($lv == 0 && $tkn->[0] eq "word" && $tkn->[1] =~ /from/i) {
				$flag = 1;
				last;
			}
			my $expr = $self->lexExpression($tkn, $tokens, $lv);

			# $lv++ if $expr->[0] eq "function";
			push @field, $expr;
		}
		push @flds, \@field if @field > 2;
		last if $flag;
		last if !@$tokens;
	}
	return (\@flds, $tkn);
}

sub _lex_tables {
	my ($self, $tkn, $tokens, $nodeName) = @_;
	my (@tbls, $lv, $tbl);
	push @tbls, "tables" if $nodeName;
	while ($tkn = shift @$tokens) {
		($tbl, $tkn) = $self->lexTable($tkn, $tokens);
		$lv++ if $tkn && $tkn->[0] eq "openBracket";
		$lv-- if $tkn && $tkn->[0] eq "closeBracket";
		push @tbls, $tbl if @$tbl;
		last if $lv == 0 && $tkn && $tkn->[0] eq "word" && $tkn->[1] =~ /where|order|having|group|limit/i;
		redo if @$tbl;
		push @tbls, $tkn if $tkn && @$tkn;
	}
	return (\@tbls, $tkn);
}

sub lexTable {
	my ($self, $tkn, $tokens) = @_;
	my $next = $tokens->[0];
	return ([], $tkn) unless $next;
	my (@syntax, $lv);
	if (   $tkn->[0] eq "word"
		&& $tkn->[1] =~ /left|right|inner|outer/i
		&& $next->[0] eq "word"
		&& lc($next->[1]) eq "join")
	{
		push @syntax, "table", $tkn, shift(@$tokens), $self->lexTableAlias(shift(@$tokens), $tokens);
		while ($tkn = shift @$tokens) {
			$lv++ if $tkn->[0] eq "openBracket";
			$lv-- if $tkn->[0] eq "closeBracket";
			last if $lv == 0 && $tkn->[0] eq "word" && $tkn->[1] =~ /where|order|having|group|limit/i;
			last if $lv == 0 && $tkn->[0] eq "symbol" && $tkn->[1] eq ",";
			my $expr = $self->lexExpression($tkn, $tokens);

			# $lv++ if $expr->[0] eq "function";
			push @syntax, $expr;
		}
	} elsif ($tkn->[0] eq "word" && $next->[0] eq "word") {
		push @syntax, "table", $self->lexTableAlias($tkn, $tokens);
		$tkn = shift(@$tokens);
	}
	return (\@syntax, $tkn);
}

sub lexTableAlias {
	my ($self, $tkn, $tokens) = @_;
	my $alias = shift(@$tokens);
	my @syntax = ($tkn, $alias);
	push @syntax, $alias = shift(@$tokens) if lc($alias->[1]) eq "as";
	$self->{tableAliases}{ $alias->[1] } = $tkn->[1];
	return @syntax;
}

sub _lex_conditions {
	my ($self, $tkn, $tokens, $nodeName) = @_;
	my (@whrs, $lv);
	push @whrs, "conditions" if $nodeName;
	while ($tkn = shift @$tokens) {
		$lv++ if $tkn->[0] eq "openBracket";
		$lv-- if $tkn->[0] eq "closeBracket";
		last if $lv == 0 && $tkn->[0] eq "word" && $tkn->[1] =~ /order|having|group|limit/i;
		my $expr = $self->lexExpression($tkn, $tokens);

		# $lv++ if $expr->[0] eq "function";
		push @whrs, $expr;
	}
	return (\@whrs, $tkn);
}

sub _lex_havingConditions {
	my ($self, $tkn, $tokens, $nodeName) = @_;
	my (@whrs, $lv);
	push @whrs, "havingConditions" if $nodeName;
	while ($tkn = shift @$tokens) {
		$lv++ if $tkn->[0] eq "openBracket";
		$lv-- if $tkn->[0] eq "closeBracket";
		last if $lv == 0 && $tkn->[0] eq "word" && $tkn->[1] =~ /order|limit/i;
		my $expr = $self->lexExpression($tkn, $tokens);

		# $lv++ if $expr->[0] eq "function";
		push @whrs, $expr;
	}
	return (\@whrs, $tkn);
}

sub lexExpression {
	my ($self, $tkn, $tokens, $level) = @_;
	my $next = $tokens->[0];
	my @syntax;

	# if ($next && $tkn->[0] eq "word" && $tkn->[1] !~ /^(?:in|or|and|not|date)$/i && $next->[0] eq "openBracket") {
	# shift(@$tokens);
	# @syntax = @$tkn;
	# $syntax[0] = "function";
	# return \@syntax;
	# }
	if ($next && $tkn->[0] eq "word" && $next->[0] eq "symbol" && $next->[1] eq ".") {
		my ($op, $field) = (shift(@$tokens), shift(@$tokens));
		push @syntax, "reference", $tkn, $op, $field;
		return \@syntax;
	}
	return $tkn;
}

sub extend {
	my ($self, $name) = @_;
	return $self->placeholders($name)
		if ref $name;

	my $tpl = Eldhelm::Database::Template->new(file => $name);
	$self->{stream} = $tpl->{stream};

	$self->{$_} = { %{ $tpl->{$_} }, %{ $self->{$_} } } foreach qw(filterPlaceholders placeholders);
	foreach my $k (keys %{ $tpl->{append} }) {
		push @{ $self->{append}{$k} }, @{ $tpl->{append}{$k} };
	}

	return $self;
}

sub placeholders {
	my ($self, $placeholders) = @_;
	$self->{placeholders} = { %{ $self->{placeholders} }, %$placeholders };
	return $self;
}

sub filter {
	my ($self, $filters) = @_;
	$self->{conditions} = { %{ $self->{conditions} }, %$filters };
	return $self;
}

sub format {
	my ($self, $format) = @_;
	$self->{format} = { %{ $self->{format} }, %$format };
	return $self;
}

sub fields {
	my ($self, $fields) = @_;
	foreach (@$fields) {
		$self->{fields}{$_} = 1;
	}
	return $self;
}

sub clearFields {
	my ($self) = @_;
	%{ $self->{fields} } = ();
	return $self;
}

sub clearFilter {
	my ($self) = @_;
	%{ $self->{conditions} } = ();
	return $self;
}

sub limit {
	my ($self, $limit) = @_;
	$self->{limit} = $limit;
	return $self;
}

sub compile {
	my ($self, $args) = @_;
	$self->placeholders($args->{placeholders}) if $args->{placeholders};
	$self->fields($args->{fields})             if $args->{fields};
	$self->format($args->{format})             if $args->{format};
	$self->filter($args->{filter})             if $args->{filter};
	$self->limit($args->{limit})               if $args->{limit};
	$self->parse;
	$self->{compiled} = $self->compileSyntax($args);
	$self->{compiled} =~ s/\[(.+?)\]/$self->compileFilters($1)." "/ge;
	return $self->{compiled};
}

sub compileSyntax {
	my ($self, $args) = @_;
	return $self->compileNode($self->{syntax}, $args);
}

sub compileNode {
	my ($self, $node, $args) = @_;
	return $self->compileNodeByName($node->[0], $node, $args);
}

sub compileNodeByName {
	my ($self, $name, $node, $args) = @_;
	confess "Can not compile node without a name: ".Dumper($node) if !$name;
	my $fn = "_compile_$name";
	if (!$self->can($fn)) {
		confess "Unexpected node $name";
		return;
	}
	return $self->$fn($node, $args);
}

sub _compile_select {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	my @compiled;
	my %clauses = map { +$_->[0] => $_ } @list;

	foreach (qw(fields tables conditions group havingConditions order limit)) {
		my $rf = $self->{$_};
		push @compiled, $self->compileNodeByName($_, $clauses{$_}, $args)
			if $clauses{$_} || (!ref $rf && $rf) || (ref $rf eq "HASH" && keys %$rf);
	}
	return join("", "SELECT\n\t", @compiled);
}

sub _compile_fields {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	push @list, @{ $self->{append_tokens_fields} } if $self->{append_tokens_fields};

	$self->converWildcardsToTokens(\@list);

	my @data;
	foreach (@list) {
		push @data, grep { $_ } $self->compileNode($_);
	}
	return join ",\n\t", @data;
}

sub _compile_field {
	my ($self, $node, $args) = @_;
	my ($alias, @list) = @$node[ 1 .. $#$node ];
	my $nm = $alias;
	$nm = $list[-1][0]     if $list[-1][0] eq "word";
	$nm = $list[-1][-1][1] if $list[-1][0] eq "reference";
	return if $nm && $self->excludeField($nm);
	return $self->formatField($nm, $alias, join("", map { $self->compileNode($_) } @list));
}

sub _compile_tables {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	push @list, @{ $self->{append_tokens_tables} } if $self->{append_tokens_tables};
	my @data;
	foreach (@list) {
		push @data, $self->compileNode($_);
	}
	return "\nFROM\n\t".join("", map { $self->compileNode($_) } @list);
}

sub _compile_table {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	return join "", map { $self->compileNode($_) } @list;
}

sub _compile_conditions {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	push @list, @{ $self->{append_tokens_conditions} } if $self->{append_tokens_conditions};
	push @list, $self->convertFilterToTokens(!scalar @list);
	my @data;
	foreach (@list) {
		push @data, $self->compileNode($_);
	}
	return "" unless @data;
	return "\nWHERE\n\t".join("", @data);
}

sub _compile_group {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	my @data;
	foreach (@list) {
		push @data, $self->compileNode($_);
	}
	return "\nGROUP ".join("", @data);
}

sub _compile_havingConditions {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];

	my @data;
	foreach (@list) {
		push @data, $self->compileNode($_);
	}
	return "\nHAVING\n\t".join("", @data);
}

sub _compile_order {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	my @data;
	foreach (@list) {
		push @data, $self->compileNode($_);
	}
	return "\nORDER ".join("", @data);
}

sub _compile_limit {
	my ($self, $node, $args) = @_;
	my @data;
	if ($self->{limit}) {
		@data = ($self->{limit});
	} else {
		my @list = @$node[ 1 .. $#$node ];
		foreach (@list) {
			push @data, $self->compileNode($_);
		}
	}
	return "\nLIMIT ".join("", @data);
}

sub _compile_reference {
	my ($self, $node, $args) = @_;
	my @list = @$node[ 1 .. $#$node ];
	return join("", map { $_->[1] } @list)." ";
}

sub _compile_string {
	my ($self, $node) = @_;
	return "'$node->[1]' ";
}

sub _compile_word {
	my ($self, $node) = @_;
	return "$node->[1] ";
}

sub _compile_function {
	my ($self, $node) = @_;
	return $node->[1];
}

sub _compile_number {
	my ($self, $node) = @_;
	return "$node->[1] ";
}

sub _compile_operator {
	my ($self, $node) = @_;
	return "$node->[1] ";
}

sub _compile_symbol {
	my ($self, $node) = @_;
	return "$node->[1] ";
}

sub _compile_openBracket {
	my ($self, $node) = @_;
	return "( ";
}

sub _compile_closeBracket {
	my ($self, $node) = @_;
	return ") ";
}

sub _compile_instruction {
	my ($self, $node) = @_;
	return $node->[1];
}

sub convertFilterToTokens {
	my ($self, $isAfterMoreTkns) = @_;
	my $fp = $self->{filterPlaceholders};
	my @list;
	my $and = [ "word", "AND" ];
	foreach my $name (grep { !$fp->{$_} } keys %{ $self->{conditions} }) {
		my $val   = $self->{conditions}{$name};
		my $alias = $self->searchFieldTableAlias($name);
		confess "You supplied the following conditions: "
			.Dumper($self->{conditions})
			."The table alias of the field `$name` is unknown. Make sure `$name` is available as a field in the tables or is defined as [$name ...]\n"
			if !$alias;
		my $fld = [ "reference", [ "word", $alias ], [ "symbol", "." ], [ "word", $name ] ];
		if (ref $val eq "ARRAY") {
			my @values = map { [ "string", $_ ], [ "symbol", "," ] } @$val;
			pop @values;
			push @list, $and, $fld, [ "word", "IN" ], ["openBracket"], @values, ["closeBracket"];
		} else {
			push @list, $and, $fld, [ "operator", "=" ], [ "string", $val ];
		}
	}
	shift @list if $isAfterMoreTkns;
	return @list;
}

sub converWildcardsToTokens {
	my ($self, $list)    = @_;
	my ($i,    @expands) = (-1);
	foreach my $f (@$list) {
		$i++;
		next if $f->[1] ne "*";
		push @expands, [ $i, $f->[2] ];
	}
	foreach my $f (reverse @expands) {
		my ($alias, @flds) = ($f->[1]);
		foreach (@{ $self->expandWildcard($alias) }) {
			push @flds, [ "field", undef, [ "reference", [ "word", $alias ], [ "symbol", "." ], [ "word", $_ ] ] ];
		}
		splice @$list, $f->[0], 1, @flds;
	}
}

sub expandWildcard {
	my ($self, $alias) = @_;
	my $table = $self->{tableAliases}{$alias};
	my $desc  = $self->descTable($table);
	return $self->{tableDescFields}{$table} ||= [ map { $_->{Field} } @$desc ];
}

sub compileFilters {
	my ($self, $name) = @_;
	return if !$name;
	my $query = $self->{filterPlaceholders}{$name};
	return unless exists $self->{conditions}{$name};
	return $query if $query !~ /\?/;
	my $values = $self->{conditions}{$name};
	return $self->compileValues($query, $values);
}

sub compileValues {
	my ($self, $query, $values) = @_;
	if (ref $values eq "ARRAY") {
		my @list = @$values;
		my $num = $query =~ tr/\?//;
		$num-- if $num < @list;
		$num--;
		foreach (0 .. $num) {
			my $v = shift @list;
			$query =~ s/\?/'$v'/;
		}
		$query =~ s/\?/join(",", map {"'$_'"} @list)/e if @list;

	} else {
		$query =~ s/\?/$values/;
	}
	return $query;
}

sub formatField {
	my ($self, $name, $alias, $expression) = @_;
	my $format = $self->{format}{$name};
	return $expression.($alias ? "AS $alias" : "") unless $format;
	return "DATE_FORMAT($expression, '$self->{defaultFormat}{date}') AS $name" if $format eq "date";
	return $expression;
}

sub getFieldType {
	my ($self, $alias, $name) = @_;
	my $table = $self->{tableAliases}{$alias};
	my $desc  = $self->descTableAsHash($table);
	return $desc->{$name}{Type};
}

sub searchFieldTableAlias {
	my ($self, $field) = @_;
	$self->{tableFieldsLookup} ||= {
		map {
			my ($a, $t) = ($_, $self->{tableAliases}{$_});
			map { +$_->{Field} => $a } @{ $self->descTable($t) }
			} keys %{ $self->{tableAliases} }
	};
	return $self->{tableFieldsLookup}{$field};
}

sub excludeField {
	my ($self, $name) = @_;
	return if !$name;
	return if !keys %{ $self->{fields} };
	return !$self->{fields}{$name};
}

1;
