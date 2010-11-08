package BSE::ImportTargetBase;
use strict;

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  my $self = bless {}, $class;

  return $self;
}

1;
