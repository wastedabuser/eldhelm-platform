package Eldhelm::Mail::Sender;

=pod

=head1 NAME

Eldhelm::Mail::Sender - A simple mail sender.

=head1 SYNOPSIS

	Eldhelm::Mail::Sender->new(
		to 		=> 'a@abc.com',
		subject => 'News',
		tpl     => 'mail.news'
	)->send;

=head1 METHODS

=over

=cut

use strict;
use Eldhelm::Util::Tool;
use Eldhelm::Util::Template;
use Eldhelm::Mail::TLS;
use MIME::Lite;
use Data::Dumper;

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<to> String - The recepient;
C<from> String - The sender;
C<replyto> String - Reply to;
C<subject> String - The subject;
C<content> String - The body of the mail;
C<tpl> String - A template instead of content;
C<tplParams> HashRef - Template compile params;
C<config> HashRef - A parsed C<config.pl> file;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {
		to            => $args{to},
		from          => $args{from},
		replyto       => $args{replyto},
		subject       => $args{subject},
		content       => $args{content},
		tpl           => $args{tpl},
		tplParams     => $args{tplParams},
		preview       => $args{preview},
		config        => $args{config},
		defaultParams => {}
	};
	bless $self, $class;

	return $self;
}

sub getConfig {
	my ($self) = @_;
	return $self->{config}{mail} || Eldhelm::Server::Child->instance->getConfig('mail');
}

=item send()

Sends mail to hte recepient.
Dies on error.

=cut

sub send {
	my ($self) = @_;
	my $cfg = $self->getConfig;
	my $data;
	if ($self->{tpl}) {
		$data = Eldhelm::Util::Template->new(
			name         => $self->{tpl},
			globalParams => $cfg->{globalTemplateParams},
			params       => Eldhelm::Util::Tool->merge($self->{defaultParams}, $self->{tplParams}),
		)->compile;
	} else {
		$data = $self->{content};
	}

	$self->{mail}        = $self->{to} || $cfg->{adminMail};
	$self->{mailData}    = $data;
	$self->{mailSubject} = sprintf($cfg->{subject}, $self->{subject});

	my $cls = $cfg->{smtp}{tls} ? 'Eldhelm::Mail::TLS' : 'MIME::Lite';
	my %mailData = (
		From => $self->{from} || $cfg->{from},
		$self->{replyto} ? ('Reply-to' => $self->{replyto}) : (),
		To       => $self->{mail},
		Subject  => $self->{mailSubject},
		Encoding => 'quoted-printable',
		Type     => 'text/html',
		Data     => $data,
	);
	my $mail = $cls->new(%mailData);
	$mail->attr('content-type.charset' => 'UTF-8');

	if ($self->{preview}) {
		print Dumper(\%mailData);
	} elsif ($cfg->{smtp}) {
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

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
