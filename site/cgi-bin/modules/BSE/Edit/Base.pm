package BSE::Edit::Base;
use strict;

# one day I might put something useful here
sub new {
  my ($class, %parms) = @_;

  return bless \%parms, $class;
}

1;
