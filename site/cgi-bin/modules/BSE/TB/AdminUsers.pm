package BSE::TB::AdminUsers;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminUser;

sub rowClass {
  return 'BSE::TB::AdminUser';
}

1;
