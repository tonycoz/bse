package BSE::TB::AdminMemberships;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminMembership;

sub rowClass {
  return 'BSE::TB::AdminMembership';
}

1;
