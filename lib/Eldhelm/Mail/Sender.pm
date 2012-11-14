package Eldhelm::Mail::Sender;

use strict;
use Eldhelm::Util::Template;
use Eldhelm::Mail::TLS;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = {
		to        => $args{to},
		from      => $args{from},
		subject   => $args{subject},
		content   => $args{content},
		tpl       => $args{tpl},
		tplParams => $args{tplParams},
		config    => $args{config},
	};
	bless $self, $class;

	return $self;
}

sub getConfig {
	my ($self) = @_;
	my $cfg = $self->{config} || Eldhelm::Server::Child->instance->{config};
	return $cfg->{mail};
}

sub send {
	my ($self) = @_;
	my $cfg = $self->getConfig;
	my $data;
	if ($self->{tpl}) {
		$data = Eldhelm::Util::Template->new(
			name   => $self->{tpl},
			params => $self->{tplParams},
		)->compile;
	} else {
		$data = $self->{content};
	}

	my $mail = Eldhelm::Mail::TLS->new(
		From => $cfg->{from},
		$self->{from} ? ('Reply-to' => $self->{from}) : (),
		To => $self->{to} || $cfg->{adminMail},
		Subject  => sprintf($cfg->{subject}, $self->{subject}),
		Encoding => "quoted-printable",
		Type     => "text/html",
		Data     => $data,
	);
	$mail->attr('content-type.charset' => 'UTF-8');

	if ($cfg->{smtp}) {
		$mail->send(
			'smtp_tls', $cfg->{smtp}{host},
			AuthUser => $cfg->{smtp}{user},
			AuthPass => $cfg->{smtp}{pass},
			Port     => $cfg->{smtp}{port} || 25
		);
	} else {
		$mail->send;
	}
}

1;
