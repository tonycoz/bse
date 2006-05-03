package BSE::ComposeMail;
use strict;
use BSE::Template;
use BSE::Mail;
use Carp 'confess';

sub new {
  my ($class, %opts) = @_;

  $opts{cfg} or die;

  bless \%opts, $class;
}

sub send {
  my ($self, %opts) = @_;

  for my $arg (qw(acts template to from subject)) {
    unless ($opts{$arg}) {
      confess "Argument $arg missing\n";
    }
  }

  my %acts = %{$opts{acts}}; # at some point we'll add extra tags here
  my $content = BSE::Template->get_page($opts{template}, $self->{cfg}, \%acts);
  
  my $mailer = BSE::Mail->new(cfg => $self->{cfg});
  $mailer->send(to => $opts{to},
		from => $opts{from},
		subject => $opts{subject},
		body => $content)
    or print STDERR "Error sending mail ", $mailer->errstr, "\n";
}

1;
