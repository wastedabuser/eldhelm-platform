package Eldhelm::Server::Handler::Json;

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

### TEST SCRIPT: 001_json_proto_messages.pl ###

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

1;