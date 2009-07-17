package BSE::TB::OrderItemOptions;
use strict;
use base 'Squirrel::Table';
use BSE::TB::OrderItemOption;

sub rowClass {
  'BSE::TB::OrderItemOption';
}

1;
