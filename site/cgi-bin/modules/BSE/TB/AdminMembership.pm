package BSE::TB::AdminMembership;
# this probably won't be used
use strict;
use base qw(Squirrel::Row);

sub columns {
  return qw/user_id group_id/;
}

1;
