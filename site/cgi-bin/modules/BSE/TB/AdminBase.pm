package BSE::TB::AdminBase;
use strict;
use base qw(Squirrel::Row);

sub columns {
  return qw/id type/;
}

1;
