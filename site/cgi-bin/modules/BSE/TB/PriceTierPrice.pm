package BSE::TB::PriceTierPrice;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.000";

sub table {
  return "bse_price_tier_prices";
}

sub columns {
  return qw(id tier_id product_id retailPrice);
}

1;
