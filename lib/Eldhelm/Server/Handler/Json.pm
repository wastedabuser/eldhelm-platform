package Eldhelm::Server::Handler::Json;

=pod

=head1 NAME

Eldhelm::Server::Handler::Json.

=head1 DESCRIPTION

This class handles the Eldhelm Platform JSON protocol. 
This protocol uses JSON encoded messages over tcp connection.

A message is constructed of two parts: header and content. For example:

	["eldhelm-json-1.1",{"len":6}]{"a":1}

C<["eldhelm-json-1.1",{"len":6}]> is the header;
C<{"a":1}> is the message.

In the header:
C<eldhelm-json-1.1> is the protocol id and version;
C<len> indicates the message length in bytes. There might be other header properties along with C<len>;

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Server::Parser::Json;
use Eldhelm::Util::Tool;
use Data::Dumper;
use Carp;

use base qw(Eldhelm::Server::Handler::RoutingHandler);

sub COMPOSER_NAME { 
	return "Eldhelm::Server::Parser::Json";
}

sub check {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	return $data =~ m/^\["eldhlem-json-\d+\.\d+\"/ ? 1 : undef;
}

### UNIT TEST: 001_json_proto_messages.pl ###

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data, $main) = @_;
	my $composer = COMPOSER_NAME;
	my $more     = "";

	$data =~ s/^(\[.+?\])//;
	my %parsed = (headerContent => $1);
	eval { ($parsed{protocolId}, $parsed{headers}) = @{ $composer->parse($parsed{headerContent}) }; };
	if ($@) {
		$main->error("Error parsing header: $@\n$data");
		return ({ len => -2 }, $data);
	}

	($parsed{protocolVersion}) = $parsed{protocolId} =~ /(\d+\.\d+)/;
	my $ln = int $parsed{headers}{contentLength};
	{
		use bytes;
		my $dln = length $data;
		if ($ln == 0) {
			$parsed{len} = 0;
			$more = $data;
		} elsif ($ln < $dln) {
			$parsed{content} = substr $data, 0, $ln;
			$more            = substr $data, $ln;
			$parsed{len}     = -1;
		} else {
			$parsed{content} = $data;
			$parsed{len}     = $ln - $dln;
		}
	}

	return (\%parsed, $more);
}

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	$self->{composer} = COMPOSER_NAME;
	bless $self, $class;

	return $self;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;