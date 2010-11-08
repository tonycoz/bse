package BSE::TB::AdminPerms;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminPerm;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::AdminPerm';
}

1;
