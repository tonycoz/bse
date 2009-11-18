package BSE::ImportTargetBase;
use strict;

sub new {
  my ($class, %opts) = @_;

  my $self = bless {}, $class;

  return $self;
}

1;
