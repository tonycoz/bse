package BSE::TB::OrderItemOptions;
use strict;
use base 'Squirrel::Table';
use BSE::TB::OrderItemOption;

our $VERSION = "1.000";

sub rowClass {
  'BSE::TB::OrderItemOption';
}

1;
