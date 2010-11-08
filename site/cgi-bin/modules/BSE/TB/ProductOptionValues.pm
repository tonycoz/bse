package BSE::TB::ProductOptionValues;
use strict;
use base 'Squirrel::Table';
use BSE::TB::ProductOptionValue;

our $VERSION = "1.000";

sub rowClass {
  'BSE::TB::ProductOptionValue';
}

1;
