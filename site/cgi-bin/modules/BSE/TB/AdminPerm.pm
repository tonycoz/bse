package BSE::TB::AdminPerm;
# this probably won't be used
use strict;
use base qw(Squirrel::Row);

our $VERSION = "1.000";

sub columns {
  return qw/object_id admin_id/;
}

1;
