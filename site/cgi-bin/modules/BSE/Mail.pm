package BSE::Mail;
use strict;
use Constants qw/:email/;

sub new {
  if ($SMTP_SERVER) {
    require 'BSE/Mail/SMTP.pm';
    return BSE::Mail::SMTP->new;
  }
  else {
    require 'BSE/Mail/Sendmail.pm';
    return BSE::Mail::Sendmail->new;
  }
}

1;

=head1 NAME

  BSE::Mail - loader class for the configured mail handler class

=head1 SYNOPSIS

  use BSE::Mail;
  my $mail = BSE::Mail->new;
  $mail->send(from=>$from, to=>$to, subject=>$subject, 
	      headers=>$headers, body=>$body)
    or die $mail->errstr;

=head1 DESCRIPTION

This class provides a wrapper around the 2 current implementations of
mail sending, either by using the sendmail program, or via SMTP to a
configured server.

=head1 SEE ALSO

  BSE::Mail::Sendmail, BSE::Mail::SMTP

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

