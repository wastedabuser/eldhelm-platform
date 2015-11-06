package Eldhelm::Mail::Bulk;

=pod

=head1 NAME

Eldhelm::Mail::Bulk - Bulk mail sending via smtp.

=head1 SYNOPSIS

	Eldhelm::Mail::Bulk->new(
		recipients => [
			{ mail => 'a@abc.com' },
			{ mail => 'b@abc.com' }
		],
		subject    => 'News',
		tpl        => 'mail.news'
	)->send;

=head1 METHODS

=over

=cut

use strict;
use Net::SMTP::TLS;
use Eldhelm::Util::Template;
use Eldhelm::Server::Child;
use Carp qw(longmess);
use Data::Dumper;
use Time::HiRes qw(usleep);

our $| = 1;

=item new(%args)

Cosntructs a new object.

C<%args> Hash - Constructor arguments;

C<recipients> String - Will parse a file;
C<from> String - Will parse a stream;
C<subject> String - The subject of the mail;
C<content> String - The content of the mail;
C<tpl> String String- The mail template instead of content;
C<tplRootPath> String - Where templates are located;
C<tplParams> HashRef - Template compile arguments;
C<config> HashRef - A parsed C<config.pl> file;
C<debug> 1 or 0 or undef - Allow debugging output;
C<limit> Number - Max number of messages to send;
C<packetSize> Number - Max number of messages to send via one connection; Defaults to 50;
C<packetWait> Number - How much time to wait in micro seconds before connecting for the next messages; Defaults to 250_000;
C<printProgress> 1 or 0 or undef - Whether to output the progress of the sending;
C<callbacks> HashRef - A hashref of subs acting as hooks to some events, see events bellow;
C<multilanguage> 1 or 0 or undef - Whether this mail template supports multiple languages;
C<allowedLangs> ArrayRef - A list of available languages. All others will be en;
C<defaultLang> String - The language of the mail defaults to en;

Events:
C<onSendError> - Triggers when there is an error in the smtp sending process;
C<onSendMail> - Triggers when the smtp accepts the message;

=cut

sub new {
	my ($class, %args) = @_;
	my $self = {
		recipients    => $args{recipients},
		from          => $args{from},
		subject       => $args{subject},
		content       => $args{content},
		tpl           => $args{tpl},
		tplRootPath   => $args{tplRootPath},
		tplParams     => $args{tplParams} || {},
		config        => $args{config},
		debug         => $args{debug},
		limit         => $args{limit},
		packetSize    => $args{packetSize} || 50,
		packetWait    => $args{packetWait} || 1_000_000 / 4,
		printProgress => $args{printProgress},
		callbacks     => $args{callbacks} || {},
		multilanguage => $args{multilanguage},
		allowedLangs  => $args{allowedLangs} || [],
		defaultLang   => $args{defaultLang} || 'en',
	};
	bless $self, $class;

	return $self;
}

sub getConfig {
	my ($self) = @_;
	return $self->{config}{mail} || Eldhelm::Server::Child->instance->getConfig('mail');
}

=item send()

Sends mail to recepients.

=cut

sub send {
	my ($self) = @_;
	my $cfg = $self->getConfig;
	my %defaultParams = (%{ $cfg->{globalTemplateParams} }, %{ $self->{tplParams} });
	$self->{defaultParams} = \%defaultParams;

	my $size  = $self->{packetSize};
	my %langs = map { +$_ => $_ } @{ $self->{allowedLangs} };
	my $limit = 0;
	my @list  = @{ $self->{recipients} };

	$self->printProgress('Sending a total of '.@list." emails.\n");
	while (@list) {

		my @packet;
		foreach (1 .. $size) {
			last unless @list;
			push @packet, shift @list;
		}

		last unless @packet;

		$self->printProgress('Sending '.@packet." emails ...\n");

		my $smtp = Net::SMTP::TLS->new(
			$cfg->{smtp}{host},
			Hello    => $cfg->{smtp}{hello},
			Port     => $cfg->{smtp}{port} || 25,
			User     => $cfg->{smtp}{user},
			Password => $cfg->{smtp}{pass}
		);

		my $i = 0;
	RCPLOOP: foreach my $rcp (@packet) {
			$i++;

			if (defined $self->{limit} && $limit >= $self->{limit}) {
				$self->printProgress("\nStopping due limit: $limit\n");
				last;
			}
			$limit++;

			my ($sender_name, $sender, $reciever, $subject, $lng) = (
				$cfg->{name}, $cfg->{from},
				$self->trim($rcp->{mail}),
				sprintf($cfg->{subject}, $self->{subject}),
				$rcp->{lang}
			);

			my $ln = $langs{$lng} || $self->{defaultLang};
			my $tpl = $self->{multilanguage} ? "$self->{tpl}_$ln" : $self->{tpl};

			my $body;
			if ($self->{tpl}) {
				$body = Eldhelm::Util::Template->new(
					rootPath => $self->{tplRootPath},
					name     => $tpl,
					params   => { %defaultParams, %$rcp },
				)->compile;
			} else {
				$body = $self->{content};
			}
			$self->printProgress(" $i($reciever;$lng;$ln)");

			my $data;
			eval {
				$smtp->mail($sender);
				$smtp->recipient($reciever);
				$smtp->data();

				$data = "From: $sender_name <$sender> \n";
				$data .= "To: <$reciever> \n";
				$data .= qq~Content-Type: text/html; charset="utf-8" \n~;
				$data .= "Mime-Version: 1.0 \n";
				$data .= "Subject: $subject \n";
				$data .= "\n";
				$data .= $body;
				$data .= "\n";
				$self->debug($data) if $self->{debug};

				$smtp->datasend($data);
				$smtp->dataend();

				$self->triggerCallback(
					'onSendMail',
					$rcp,
					{   subject => $subject,
						data    => $data
					}
				);
				1;
			} or do {
				$self->debug(Dumper $rcp);
				$self->debug(longmess $@);
				$self->triggerCallback(
					'onSendError',
					$rcp,
					{   subject => $subject,
						data    => $data
					},
					$@
				);
				last RCPLOOP;
			};

		}

		$smtp->quit;

		$self->printProgress("\nDone\n");

		last if defined $self->{limit} && $limit >= $self->{limit};

		usleep $self->{packetWait};
	}

	return $self;
}

sub trim {
	my ($self, $string) = @_;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

sub triggerCallback {
	my ($self, $name, @more) = @_;
	my $fn = $self->{callbacks}{$name};
	return unless $fn;

	return $self->$fn(@more);
}

sub printProgress {
	my ($self, $msg) = @_;
	return unless $self->{printProgress};
	print $msg;
	return;
}

sub debug {
	my ($self, $msg) = @_;

	print "$msg\n";
	return;
}

=back

=head1 AUTHOR

Andrey Glavchev @ Essence Ltd. (http://essenceworks.com)

=head1 LICENSE

This software is Copyright (c) 2011-2015 of Essence Ltd.

Distributed undert the MIT license.
 
=cut

1;
