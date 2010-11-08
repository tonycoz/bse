package BSE::TB::AdminMembership;
# this probably won't be used
use strict;
use base qw(Squirrel::Row);

our $VERSION = "1.000";

sub columns {
  return qw/user_id group_id/;
}

1;
