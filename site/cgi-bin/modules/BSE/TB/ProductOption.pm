package BSE::TB::ProductOption;
use strict;
use base 'Squirrel::Row';

sub columns {
  return qw/id product_id name type global_ref display_order enabled default_value/;
}

sub table {
  "bse_product_options";
}

sub defaults {
  return
    (
     global_ref => undef,
     enabled => 1,
     type => "select",
     default_value => 0,
    );
}

sub values {
  my ($self) = @_;

  require BSE::TB::ProductOptionValues;
  return sort { $a->{display_order} <=> $b->{display_order} }
    BSE::TB::ProductOptionValues->getBy(product_option_id => $self->{id});
}

sub key {
  my $self = shift;
  return "prodopt_" . $self->id;
}

1;
