package Eldhelm::Util::Url;

use strict;
use Carp;

sub new {
	my ($class, %args) = @_;
	my $self = { uri => $args{uri}, };
	bless $self, $class;

	$self->parse($self->{uri}) if $self->{uri};

	return $self;
}

sub parse {
	my ($self, $uri) = @_;
	$uri =~ /^([^\?]+)\??(.*)#?([^#]*)$/;
	$self->{url}         = $1;
	$self->{queryString} = $2;
	$self->{anchor}      = $3;
	return $self;
}

sub compileWithFolder {
	my ($self, $folder) = @_;
	return $self->compile("$self->{url}/$folder");
}

sub compileWithParams {
	my ($self, $params) = @_;
	return $self->compile(
		undef,
		join("&",
			$self->{queryString} || (),
			map { "$_=".$self->urlencode($params->{$_}) } sort { $a cmp $b } keys %{$params})
	);
}

sub compile {
	my ($self, $url, $queryString, $anchor) = @_;
	$url         ||= $self->{url};
	$queryString ||= $self->{queryString};
	$anchor      ||= $self->{anchor};
	return join "?", $url, $queryString || (), $anchor ? "#$anchor" : ();
}

sub urlencode {
	my ($self, $str) = @_;
	$str =~ s/ /+/g;
	$str =~ s/([^A-Za-z0-9\+-])/sprintf("%%%02X", ord($1))/seg;
	return $str;
}

1;
