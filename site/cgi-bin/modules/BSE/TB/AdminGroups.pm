package BSE::TB::AdminGroups;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminGroup;

sub rowClass {
  return 'BSE::TB::AdminGroup';
}

1;
