package BSE::TB::AdminPerms;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminPerm;

sub rowClass {
  return 'BSE::TB::AdminPerm';
}

1;
