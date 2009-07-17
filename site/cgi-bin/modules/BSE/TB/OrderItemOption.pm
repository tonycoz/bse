package BSE::TB::OrderItemOption;
use strict;
use base 'Squirrel::Row';

sub table {
  "bse_order_item_options";
}

sub columns {
  return qw/id order_item_id original_id name value display display_order/;
}

1;
