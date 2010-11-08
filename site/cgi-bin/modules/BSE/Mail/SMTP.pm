package BSE::Mail::SMTP;
use strict;
use vars qw/@ISA/;
use Net::SMTP;

our $VERSION = "1.000";

@ISA = qw/BSE::Mail/;

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class;
}

sub send {
  my ($self, %args) = @_;
  
  for (qw/to from subject body/) {
    $args{$_}
      or return $self->_error("$_ argument missing");
  }

  $args{headers} ||= '';

  $args{headers} =~ /\x0A\s*\x0A/ 
    and return $self->_error("headers contains a blank line");
  $args{headers} && $args{headers} !~ /\x0A$/
    and return $self->_error("headers not terminated by a newline");
  $args{headers} =~ /^\s/
    and return $self->_error("headers starts with whitespace");

  my $cfg = $self->{cfg};

  my $subject = $args{subject};
  my $to = $args{to};
  if ($cfg->entry('basic', 'test', 0)) {
    my $test_address = $cfg->entry('mail', 'test_address');
    if ($test_address) {
      $subject = "[bse test] $subject";
      $to = $test_address;
    }
    else {
      return $self->_error("BSE in test mode but mail.test_address not set");
    }
  }

  my $server = $cfg->entryErr('mail', 'smtp_server');
  my $helo = $cfg->entryErr('mail', 'helo');
  my $smtp = Net::SMTP->new($server, Hello=>$helo)
    or return $self->_error("Cannot connect to mail server: $!");
  $smtp->mail($args{from})
    or return $self->_error("mail command failed: ".$smtp->message);
  $smtp->to($to)
    or return $self->_error("RCPT command failed: ".$smtp->message);
  if ($args{bcc}) {
    $smtp->to($args{bcc})
      or return $self->_error("RCPT command failed (BCC): ".$smtp->message);
  }
  $smtp->data()
    or return $self->_error("DATA command failed: ".$smtp->message);
  $smtp->datasend("To: $to\n");
  $smtp->datasend("From: $args{from}\n");
  $smtp->datasend("Subject: $subject\n");
  $smtp->datasend($args{headers}) if $args{headers};
  $smtp->datasend("\n");
  $smtp->datasend($args{body});
  $smtp->dataend()
    or return $self->_error("data stream error: ",$smtp->message);
  $smtp->close();

  return 1;
}

1;
