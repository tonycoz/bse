package BSE::Request;
use strict;
use base 'BSE::Request::Base';

our $VERSION = "1.002";

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->{cache_stats} = $self->{cfg}->entry('debug', 'cache_stats', 0);
  if ($self->{cache_stats}) {
    @{$self}{qw/siteuser_calls siteuser_cached has_access_cached has_access_total/} = ( 0, 0, 0, 0 );
  }

  $self;
}

sub _make_session {
  my $self = shift;

  $self->{nosession}
    and return;

  require BSE::Session;
  my %session;
  BSE::Session->tie_it(\%session, $self->{cfg});
  $self->{session} = \%session;
}

sub clear_session {
  my $self = shift;

  if (my $session = delete $self->{session}) {
    delete @{$session}{grep $_ ne "_session_id", keys %$session};
    BSE::Session->clear($session);
  }
}

1;
