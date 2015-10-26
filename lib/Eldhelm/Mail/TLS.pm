package Eldhelm::Mail::TLS;

use strict;
use warnings;
use Net::SMTP::TLS;

use parent 'MIME::Lite';


=head1 NAME

Eldhelm::Mail::TLS - adds send by SMTP+TLS to MIME::Lite

=head1 SYNOPSIS

# Create a multipart message (i.e., one with attachments) and send it
# via SMTP+TLS

### Create a new multipart message:
$msg = Eldhelm::Mail::TLS->new(
	From    => 'me@myhost.com',
	To      => 'you@yourhost.com',
	Cc      => 'some@other.com, some@more.com',
	Subject => 'A message with 2 parts...',
	Type    => 'multipart/mixed'
);

### Add parts (each "attach" has same arguments as "new"):
$msg->attach(
	Type     => 'TEXT',
	Data     => "Here's the GIF file you wanted"
);
$msg->attach(
	Type     => 'image/gif',
	Path     => 'aaa000123.gif',
	Filename => 'logo.gif',
	Disposition => 'attachment'
);
### use Net:SMTP to do the sending
$msg->send('smtp_tls','smtp.gmail.com', User => 'example@gmail.com', Password => 'yupi' );


=head1 DESCRIPTION

L<MIME::Lite> is great, until you need to send your messages to a server
that requires TLS, like Google GMail servers.

This class extends L<MIME::Lite> to provide a new send method,
C<smtp_tls>, that allows you to use such servers.
 
=head1 AUTHOR

Pedro Melo (https://github.com/melo)
 
=cut


## FIXME: a very large part of this is duplicated from send_by_smtp,
## move them to a common utility, reuse with parent MIME::Lite
my @_net_smtp_tls_opts = qw( Hello Port Timeout User Password );

sub send_by_smtp_tls {
  my ($self, $hostname, %args) = @_;

  # We may need the "From:" and "To:" headers to pass to the
  # SMTP mailer also.
  $self->{last_send_successful} = 0;

  my @hdr_to = MIME::Lite::extract_only_addrs(scalar $self->get('To'));
  if ($MIME::Lite::AUTO_CC) {
    foreach my $field (qw(Cc Bcc)) {
      push @hdr_to, MIME::Lite::extract_only_addrs($_) for $self->get($field);
    }
  }
  Carp::croak "send_by_smtp: nobody to send to for host '$hostname'?!\n"
    unless @hdr_to;

  $args{To}   ||= \@hdr_to;
  $args{From} ||= MIME::Lite::extract_only_addrs(scalar $self->get('Return-Path'));
  $args{From} ||= MIME::Lite::extract_only_addrs(scalar $self->get('From'));

  # Possibly authenticate
  if (  defined $args{AuthUser}
    and defined $args{AuthPass}
    and !$args{NoAuth})
  {
    $args{User}     = $args{AuthUser};
    $args{Password} = $args{AuthPass};
  }

  # Create SMTP client.
  # MIME::Lite::SMTP::TLS is just a wrapper giving a print method
  # to the SMTP object.

  my %opts = MIME::Lite::__opts(\%args, @_net_smtp_tls_opts);
  my $smtp = MIME::Lite::SMTP::TLS->new($hostname, %opts);

  $smtp->mail($args{From});
  $smtp->recipient(@{$args{To}});
  $smtp->data();
  $self->print_for_smtp($smtp);
  $smtp->dataend();
  $smtp->quit;

  return $self->{last_send_successful} = 1;
}


package MIME::Lite::SMTP::TLS;

#============================================================
# This class just adds a print() method to Net::SMTP.
# Notice that we don't use/require it until it's needed!

use strict;
use warnings;
use parent 'Net::SMTP::TLS';

sub print {
  my $smtp = shift;
  $MIME::Lite::DEBUG and MIME::Lite::SMTP::_hexify(join("", @_));
  $smtp->datasend(@_);
}


1;
