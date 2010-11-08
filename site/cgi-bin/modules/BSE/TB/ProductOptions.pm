package BSE::TB::ProductOptions;
use strict;
use base 'Squirrel::Table';
use BSE::TB::ProductOption;

our $VERSION = "1.000";

sub rowClass {
  'BSE::TB::ProductOption';
}

1;
