package BSE::Mail::Sendmail;
use strict;
use Constants qw/:email/;
use vars qw/@ISA/;

@ISA = qw/BSE::Mail/;

sub new {
  my ($class) = @_;

  return bless {}, $class;
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

  open MAIL, "| $SHOP_SENDMAIL -t -odi"
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
