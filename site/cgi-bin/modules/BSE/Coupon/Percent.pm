package BSE::Coupon::Percent;
use parent 'BSE::Coupon::Base';
use strict;

our $VERSION = "1.002";

sub config_fields {
  my ($class) = @_;

  return
    {
     discount_percent =>
     {
      description => "Discount",
      required => 1,
      width => 5,
      htmltype => "text",
      rules => "coupon_percent",
      units => "%",
      order => 1,
     },
    };
}

sub config_rules {
  return
    (
     coupon_percent =>
     {
      real => '0 - 100',
     },
    );
}

sub config_valid {
  1;
}

sub class_description {
  "Simple percentage cart discount";
}

sub is_active {
  my ($self, $coupon, $cart) = @_;

  $self->test_all_tiers_match($coupon, $cart)
    or return ( 0, "One or more products are already discounted" );

  1;
}

sub product_valid {
  my ($self, $coupon, $cart, $index) = @_;

  return $self->test_tier_matches($coupon, $cart, $index);
}

sub discount {
  my ($self, $coupon, $cart) = @_;

  return int($cart->total_cost * $self->{config}{discount_percent} / 100);
}

sub describe {
  my ($self) = @_;

  sprintf("%.1f%% cart discount", $self->{config}{discount_percent});
}

1;
