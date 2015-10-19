package Eldhelm::Mail::Sender;

use strict;
use Eldhelm::Util::Tool;
use Eldhelm::Util::Template;
use Eldhelm::Mail::TLS;
use MIME::Lite;
use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = {
		to        => $args{to},
		from      => $args{from},
		replyto   => $args{replyto},
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
	return $self->{config}{mail} || Eldhelm::Server::Child->instance->getConfig("mail");
}

sub send {
	my ($self) = @_;
	my $cfg = $self->getConfig;
	my $data;
	if ($self->{tpl}) {
		$data = Eldhelm::Util::Template->new(
			name   => $self->{tpl},
			params => Eldhelm::Util::Tool::merge({}, $cfg->{globalTemplateParams}, $self->{tplParams}),
		)->compile;
	} else {
		$data = $self->{content};
	}

	my $cls = $cfg->{smtp}{tls} ? 'Eldhelm::Mail::TLS' : 'MIME::Lite';
	my $mail = $cls->new(
		From => $self->{from} || $cfg->{from},
		$self->{replyto} ? ('Reply-to' => $self->{replyto}) : (),
		To => $self->{to} || $cfg->{adminMail},
		Subject  => sprintf($cfg->{subject}, $self->{subject}),
		Encoding => "quoted-printable",
		Type     => "text/html",
		Data     => $data,
	);
	$mail->attr('content-type.charset' => 'UTF-8');

	if ($cfg->{smtp}) {
		$mail->send(
			($cfg->{smtp}{tls} ? 'smtp_tls' : 'smtp'), $cfg->{smtp}{host},
			AuthUser => $cfg->{smtp}{user},
			AuthPass => $cfg->{smtp}{pass},
			Port     => $cfg->{smtp}{port} || 25
		);
	} else {
		$mail->send;
	}
}

1;
