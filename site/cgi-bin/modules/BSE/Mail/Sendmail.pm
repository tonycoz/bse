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
  my $sendmail = $cfg->entry('mail', 'sendmail') || '/usr/lib/sendmail';
  my $opts = $cfg->entry('mail', 'sendmail_opts') || '-t -oi';
  # redirect to /dev/null so we don't keep stdout open in a CGI
  open MAIL, "| $sendmail $opts >/dev/null"
    or return $self->_error("Cannot open pipe to sendmail");
  print MAIL <<EOS;
From: $args{from}
To: $args{to}
Subject: $args{subject}
$args{headers}
$args{body}
EOS
  close MAIL
    or return $self->_error("close returned zero (\$?=$?)");

  return 1;
}

1;
