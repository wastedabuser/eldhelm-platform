package Eldhelm::Util::Url;

=pod

=head1 NAME

Eldhelm::Util::Url - A utility class for parsing and creating URLs.

=head1 SYNOPSIS

	my $u = Eldhelm::Util::Url->new(
		uri => 'abc.com?a=1&b=2'
	);
	
	$u->compileWithParams({ c => 3 });
	# abc.com?a=1&b=2&c=3
	
	$u->compileWithFolder('def');
	# abc.com/def?a=1&b=2&c=3

=head1 METHODS

=over

=cut

use strict;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = { uri => $args{uri}, };
	bless $self, $class;

	$self->parse($self->{uri}) if $self->{uri};

	return $self;
}

=item parse($uri) self

Parses a URI.

C<$uri> String - The URI to be parsed.

=cut

sub parse {
	my ($self, $uri) = @_;
	$uri =~ /^([^\?]+)\??(.*)#?([^#]*)$/;
	$self->{url}         = $1;
	$self->{queryString} = $2;
	$self->{anchor}      = $3;
	return $self;
}

=item compileWithFolder($folder) String

Compiles and url with the additional folder.

C<$folder> String - The folder to be appended;

=cut

sub compileWithFolder {
	my ($self, $folder) = @_;
	return $self->compile("$self->{url}/$folder");
}

=item compileWithParams($params) String

Compiles an url with the additional params.

C<$params> String - The parameters to be appended;

=cut

sub compileWithParams {
	my ($self, $params) = @_;
	return $self->compile(
		undef,
		join("&",
			$self->{queryString} || (),
			map { "$_=".$self->urlencode($params->{$_}) } sort { $a cmp $b } keys %{$params})
	);
}

=item compile($url, $queryString, $anchor) String

Compiles an url with attributes.

C<$url> String - The url to be compiled;
C<$queryString> String - Adds or replaces the query string;
C<$anchor> String - Adds or replaces an anchor;

=cut

sub compile {
	my ($self, $url, $queryString, $anchor) = @_;
	$url         ||= $self->{url};
	$queryString ||= $self->{queryString};
	$anchor      ||= $self->{anchor};
	return join "?", $url, $queryString || (), $anchor ? "#$anchor" : ();
}

=item urlencode($str) String

Encodes a string into a url encoded string.

C<$str> String - The string to be encoded.

=cut

sub urlencode {
	my ($self, $str) = @_;
	$str =~ s/([^A-Za-z0-9\-])/sprintf("%%%02X", ord($1))/seg;
	return $str;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
