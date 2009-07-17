package BSE::TB::ProductOptionValues;
use strict;
use base 'Squirrel::Table';
use BSE::TB::ProductOptionValue;

sub rowClass {
  'BSE::TB::ProductOptionValue';
}

1;
