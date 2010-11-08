package BSE::TB::AdminBase;
use strict;
use base qw(Squirrel::Row);

our $VERSION = "1.000";

sub columns {
  return qw/id type/;
}

1;
