package BSE::Mail::Sendmail;
use strict;
use vars qw/@ISA/;

@ISA = qw/BSE::Mail/;

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class;
}

sub send {
  my ($self, %args) = @_;
  
  my $cfg = $self->{cfg};

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

  if ($args{bcc}) {
    $args{headers} = "Bcc: $args{bcc}\n".$args{headers};
  }
  if ($cfg->entry('mail', 'set_errors_to_from', 1)) {
    $args{headers} = "Errors-To: $args{from}\n" . $args{headers};
  }

  my $to = $args{to};
  my $subject = $args{subject};
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
  if ($args{to_name} && $args{to_name} =~ /^[\w ]+$/) {
    $to = "$args{to_name} <$to>";
  }
  my $from = $args{from};
  if ($args{from_name} && $args{from_name} =~  /^[\w ]+$/) {
    $from = "$args{from_name} <$from>";
  }
  my $sendmail = $cfg->entry('mail', 'sendmail') || '/usr/lib/sendmail';
  my $opts = $cfg->entry('mail', 'sendmail_opts') || '-t -oi';
  # redirect to /dev/null so we don't keep stdout open in a CGI
  open MAIL, "| $sendmail $opts >/dev/null"
    or return $self->_error("Cannot open pipe to sendmail");
  print MAIL <<EOS;
From: $from
To: $to
Subject: $subject
$args{headers}
$args{body}
EOS
  close MAIL
    or return $self->_error("close returned zero (\$?=$?)");

  return 1;
}

1;
