package BSE::TB::AdminPerm;
# this probably won't be used
use strict;
use base qw(Squirrel::Row);

sub columns {
  return qw/object_id admin_id/;
}

1;
