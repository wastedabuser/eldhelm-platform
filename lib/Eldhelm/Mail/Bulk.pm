package Eldhelm::Mail::Bulk;

use strict;
use Net::SMTP::TLS;
use Eldhelm::Util::Template;
use Eldhelm::Server::Child;
use Carp qw(longmess);
use Data::Dumper;
use Time::HiRes qw(usleep);

our $| = 1;

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
		defaultLang   => $args{defaultLang} || "en",
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
	my %defaultParams = (%{ $cfg->{globalTemplateParams} }, %{ $self->{tplParams} });
	my $size          = $self->{packetSize};
	my %langs         = map { +$_ => $_ } @{ $self->{allowedLangs} };
	my $limit         = 0;
	my @list          = @{ $self->{recipients} };

	$self->printProgress("Sending a total of ".@list." emails.\n");
	while (@list) {

		my @packet;
		foreach (1 .. $size) {
			last unless @list;
			push @packet, shift @list;
		}

		last unless @packet;

		$self->printProgress("Sending ".@packet." emails ...\n");

		my $smtp = Net::SMTP::TLS->new(
			$cfg->{smtp}{host},
			Hello    => $cfg->{smtp}{hello},
			Port     => $cfg->{smtp}{port} || 25,
			User     => $cfg->{smtp}{user},
			Password => $cfg->{smtp}{pass}
		);

		my $i = 0;
		foreach my $rcp (@packet) {
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

			eval {

				$smtp->mail($sender);
				$smtp->recipient($reciever);
				$smtp->data();

				my $data = "From: $sender_name <$sender> \n";
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
			};

			if ($@) {
				$self->debug(Dumper $rcp);
				$self->debug(longmess $@);
				$self->triggerCallback("onSendError", $rcp, $@);
			} else {
				$self->triggerCallback("onSendMail", $rcp);
			}

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

1;
