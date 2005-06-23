package BSE::Mail;
use strict;
use Constants;
use Carp qw/confess/;

sub new {
  my ($class, %opts) = @_;
  my $cfg = $opts{cfg}
    or confess "No cfg parameter supplied";
  if ($cfg->entry('mail', 'smtp_server')) {
    require 'BSE/Mail/SMTP.pm';
    return BSE::Mail::SMTP->new(%opts);
  }
  else {
    require 'BSE/Mail/Sendmail.pm';
    return BSE::Mail::Sendmail->new(%opts);
  }
}

sub _error {
  my ($self, @msg) = @_;

  $self->{errstr} = "@msg";

  return;
}

sub errstr {
  my ($self) = @_;

  $self->{errstr};
}

sub complex_mail {
  my ($self, %opts) = @_;

  my $cfg = $self->{cfg};
  my $section = $opts{section}
    or confess "No section supplied to complex_mail";
  my $template = $opts{template}
    or confess "No template supplied to complex_mail";
  my $acts = $opts{acts}
    or confess "No acts supplied to complex_mail";

  require BSE::Template;
  # other tags will be added here
  my %acts =
    (
     %$acts,
    );

  my $subject_alt = $cfg->entry($section, 'subject');
  if ($subject_alt) {
    # do template replacement on the subject
    my $subject = BSE::Template->replace_template($subject_alt, \%acts);
    
    # subject may no contain newlines, and tab is bad too
    $subject =~ tr[\x0a\x0d\t][ ]s;
    $opts{subject} = $subject;
  }

  my $content = BSE::Template->get_page($template, $cfg, \%acts);
  return $self->send(%opts, body=>$content);
}


1;

=head1 NAME

  BSE::Mail - loader class for the configured mail handler class

=head1 SYNOPSIS

  use BSE::Mail;
  my $mail = BSE::Mail->new(cfg=>$cfg);
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

