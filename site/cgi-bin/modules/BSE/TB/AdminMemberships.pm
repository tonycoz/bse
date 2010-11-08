package BSE::TB::AdminMemberships;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminMembership;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::AdminMembership';
}

1;
