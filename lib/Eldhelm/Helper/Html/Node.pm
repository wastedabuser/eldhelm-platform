package Eldhelm::Helper::Html::Node;

=pod

=head1 NAME

Eldhelm::Helper::Html::Node - A utility for compiling html from a structure.

=head1 SYNOPSIS

This is a static class.

=head1 METHODS

=over

=cut

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

=item compilePage($ref) String

Same as C<compileRef>, but wraps the output with the html and body tags.

C<$ref> Mixed - A structure to be compiled;

=cut

sub compilePage {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref) = @_;
	
	return compileRef(["html", ["body", $ref]]);
}

=item compileRef($ref) String

Compiles a structure recursively to html stream.

C<$ref> Mixed - A structure to be compiled;

	Eldhelm::Helper::Html::Node->compileRef([
		'div',
		{ class => 'myClass' }
		['p', 'My text']
	]);
	
	# compiles (with propper identation)
	# <div class="myClass"><p>My text</p></div>

=cut

sub compileRef {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($ref, $level) = @_;
	
	return compileNode($ref, $level) unless ref $ref->[0];
	return join "\n", map { compileNode($_, $level) } @$ref;
}

### UNIT TEST: 200_html_helper_node.pl ###

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

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;