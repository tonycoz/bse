package BSE::Request;
use strict;
use BSE::Session;
use base 'BSE::Request::Base';

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  my %session;
  BSE::Session->tie_it(\%session, $self->{cfg});
  $self->{session} = \%session;
  $self->{cache_stats} = $self->{cfg}->entry('debug', 'cache_stats', 0);
  if ($self->{cache_stats}) {
    @{$self}{qw/siteuser_calls siteuser_cached has_access_cached has_access_total/} = ( 0, 0, 0, 0 );
  }

  $self;
}

1;
