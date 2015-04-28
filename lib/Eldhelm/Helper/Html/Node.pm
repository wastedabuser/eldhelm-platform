package Eldhelm::Helper::Html::Node;

use strict;
use Carp;

sub enc {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($str) = @_;
	$str =~ s/&/&amp;/g;
	$str =~ s/"/&quot;/g;
	$str =~ s/</&lt;/g;
	$str =~ s/>/&gt;/g;
	return $str;
}

sub compilePage {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref) = @_;
	
	return compileRef(["html", ["body", $ref]]);
}

sub compileRef {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref, $level) = @_;
	
	return compileNode($ref, $level) unless ref $ref->[0];
	return join "\n", map { compileNode($_, $level) } @$ref;
}

sub compileNode {
	my ($ref, $level) = @_;
	
	my ($name, $props, $content) = @$ref;
	
	my $inline;
	$inline = 1 if $content && $content !~ /\n/;
	
	if (ref $props eq "ARRAY") {
		$content = compileRef($props, $level + 1);
	} elsif (!ref $props) {
		$content = $props;
		$inline = 1 if $content !~ /\n/;
	} elsif (ref $content eq "ARRAY") {
		$content = compileRef($content, $level + 1);
	}
	
	my $compiledProps;
	$compiledProps = " ".join " ", map { qq~$_="~.enc($props->{$_}).'"' } keys %$props if ref $props eq "HASH";
	
	my $idn = join("", map { "\t" } 1 .. $level );
	return $idn.$content unless $name;
	return "$idn<$name$compiledProps>$content</$name>" if $inline;
	return "$idn<$name$compiledProps>\n$content\n$idn</$name>";	
}

1;