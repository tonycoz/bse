package BSE::TB::ProductOptions;
use strict;
use base 'Squirrel::Table';
use BSE::TB::ProductOption;

sub rowClass {
  'BSE::TB::ProductOption';
}

1;
