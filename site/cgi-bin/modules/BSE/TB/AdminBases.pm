package BSE::TB::AdminBases;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminBase;

sub rowClass {
  return 'BSE::TB::AdminBase';
}

1;
