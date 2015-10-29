package Eldhelm::Server::Handler::Base64;

=pod

=head1 NAME

Eldhelm::Server::Handler::Base64

=head1 DESCRIPTION

Basicly the same as L<Eldhelm::Server::Handler::Json>.
The only difference is that messages are Base64 encoded.

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Server::Parser::Base64;
use Eldhelm::Util::Tool;
use Data::Dumper;
use Carp;

use base qw(Eldhelm::Server::Handler::RoutingHandler);

sub COMPOSER_NAME {
	return "Eldhelm::Server::Parser::Base64";
}

sub check {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data) = @_;
	return $data =~ m/^BASE64ELDHELM\d{2}/ ? 1 : undef;
}

sub parse {
	shift @_ if $_[0] eq __PACKAGE__;
	my ($data, $main) = @_;
	my $composer = COMPOSER_NAME;
	my $more     = "";

	$data =~ s/^(BASE64ELDHELM\d{2})(.+?)PAYLOAD//;
	my %parsed = (protocolId => $1, headerContent => $2);
	eval { $parsed{headers} = $composer->parse($parsed{headerContent}) };
	if ($@) {
		$main->error("Error parsing header: $@\n$data");
		return ({ len => -2 }, $data);
	}

	($parsed{protocolVersion}) = $parsed{protocolId} =~ /(\d+)$/;
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