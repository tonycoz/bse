package BSE::TB::ProductOptionValue;
use strict;
use base "Squirrel::Row";

sub columns {
  return qw/id product_option_id value display_order/;
}

sub table {
  "bse_product_option_values";
}

sub option {
  my ($self) = @_;

  require BSE::TB::ProductOptions;
  return BSE::TB::ProductOptions->getByPkey($self->{product_option_id});
}

1;
