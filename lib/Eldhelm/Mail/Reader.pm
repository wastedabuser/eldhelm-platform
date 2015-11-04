package Eldhelm::Mail::Reader;

use strict;
use Net::IMAP::Client;
use Email::MIME;
use Data::Dumper;

our $| = 1;

sub new {
	my ($class, %args) = @_;
	my $self = {
		config            => $args{config},
		debug             => $args{debug},
		callbacks         => $args{callbacks} || {},
		filter            => $args{filter} || [],
		expungeAfterCount => $args{expungeAfterCount} || 10,
		mailConfigNs      => $args{mailConfigNs} || 'imap',
	};
	bless $self, $class;

	return $self;
}

sub getConfig {
	my ($self) = @_;
	return $self->{config}{mail} || Eldhelm::Server::Child->instance->getConfig('mail');
}

sub read {
	my ($self) = @_;
	$self->debug('Connecting ...');
	my $imapCfg = $self->getConfig->{ $self->{mailConfigNs} };
	my $imap = $self->{imap} = Net::IMAP::Client->new(
		server => $imapCfg->{host},
		user   => $imapCfg->{user},
		pass   => $imapCfg->{pass},
		ssl    => 1,
		port   => $imapCfg->{port} || 993,
	) or die 'Could not connect to IMAP server: '.Dumper($imapCfg);

	$self->debug("Logging in $imapCfg->{user}");
	$imap->login or die('Login failed: '.$imap->last_error);
	$imap->select('INBOX');
	$self->debug('Logged in!');

	my $filter = $self->{filter};
	my $ei     = 0;
	if (@$filter) {

		$self->debug('Searching ...');
		my %messages;
		foreach my $f (@$filter) {
			$self->debug('Running filter: '.Dumper($f));
			if (ref $f eq 'HASH') {
				$messages{$_} = 1 foreach @{ $imap->search($f) };
			}
		}
		my @msgs = keys %messages;
		$self->debug('Found '.scalar(@msgs).' messages');

		foreach (@msgs) {
			$self->debug("Parsing message $_");
			my $data = $imap->get_rfc822_body($self->{current_msg_id} = $_);
			my $parsed = $self->triggerCallback('onParseMail', $$data, Email::MIME->new($$data));
			next unless $parsed;

			$self->debug("Processing message $_");
			$self->triggerCallback('onProcessMail', $parsed);

			$ei++;

			if ($ei >= $self->{expungeAfterCount}) {
				$self->debug('Expunge!');
				$imap->expunge;
				$ei = 0;
			}
		}
	}

	if ($ei > 0) {
		$self->debug('Expunge!');
		$imap->expunge;
	}

}

sub deleteCurrentMessage {
	my ($self) = @_;
	my ($imap, $id) = ($self->{imap}, $self->{current_msg_id});

	# $imap->copy([$id], 'Trash');
	# $imap->add_flags([$id], '\\Deleted');
	$imap->delete_message($id);
	$self->debug("Deleted $id");
	return;
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
	return unless $self->{debug};
	print "$msg\n";
	return;
}

1;
