package BSE::TB::AdminBases;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminBase;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::AdminBase';
}

1;
