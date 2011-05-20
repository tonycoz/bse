package BSE::TB::PriceTierPrices;
use strict;
use base 'Squirrel::Table';
use BSE::TB::PriceTierPrice;

our $VERSION = "1.000";

sub rowClass {
  return "BSE::TB::PriceTierPrice";
}

1;
