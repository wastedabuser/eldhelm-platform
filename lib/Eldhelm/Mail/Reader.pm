package Eldhelm::Mail::Reader;

use strict;
use Net::IMAP::Client;
use Data::Dumper;

our $| = 1;

sub new {
	my ($class, %args) = @_;
	my $self = {
		config    => $args{config},
		debug     => $args{debug},
		callbacks => $args{callbacks} || {},
		filter    => $args{filter} || [],
	};
	bless $self, $class;

	return $self;
}

sub getConfig {
	my ($self) = @_;
	return $self->{config}{mail} || Eldhelm::Server::Child->instance->getConfig("mail");
}

sub read {
	my ($self) = @_;
	my $cfg = $self->getConfig;

	my $imap = $self->{imap} = Net::IMAP::Client->new(
		server => $cfg->{imap}{host},
		user   => $cfg->{imap}{user},
		pass   => $cfg->{imap}{pass},
		ssl    => 1,
		port   => $cfg->{imap}{port} || 993,
	) or die "Could not connect to IMAP server";

	$imap->login or die('Login failed: '.$imap->last_error);
	$imap->select('INBOX');

	my $filter = $self->{filter};
	if (@$filter) {

		my @messages;
		foreach (@$filter) {
			push @messages, @{ $imap->search($_) } if ref $_ eq "HASH";
		}

		foreach (@messages) {
			my $data = $imap->get_rfc822_body($self->{current_msg_id} = $_);
			my $parsed = $self->triggerCallback("onParseMail", $$data);
			next unless $parsed;
			$self->triggerCallback("onProcessMail", $parsed);
		}
	}

	$imap->expunge;

}

sub deleteCurrentMessage {
	my ($self) = @_;
	my ($imap, $id) = ($self->{imap}, $self->{current_msg_id});
	$imap->copy([$id], 'Trash');
	$imap->add_flags([$id], '\\Deleted');
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

	print "$msg\n";
	return;
}

1;
