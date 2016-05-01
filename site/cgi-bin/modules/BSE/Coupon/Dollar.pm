package BSE::Coupon::Dollar;
use parent 'BSE::Coupon::Base';
use strict;

our $VERSION = "1.003";

sub config_fields {
  my ($class) = @_;

  return
    {
     min_cart =>
     {
      description => "Min Cart Value",
      required => 1,
      width => 5,
      htmltype => "text",
      rules => "money",
      type => "money",
      order => 1,
     },
     discount_dollars =>
     {
      description => "Discount \$",
      required => 1,
      width => 5,
      htmltype => "text",
      rules => "money",
      type => "money",
      order => 2,
     },
    };
}

sub config_valid {
  1;
}

sub class_description {
  "Simple dollar cart discount";
}

sub is_active {
  my ($self, $coupon, $cart) = @_;

  $self->test_all_tiers_match($coupon, $cart)
    or return ( 0, "One or more products are already discounted" );
  unless ($cart->total_cost >= $self->{config}{min_cart}) {
    require BSE::Util::Format;
    return ( 0, sprintf("You need \$%s of items in the cart for the discount",
			BSE::Util::Format::bse_number("money", $self->{config}{min_cart})) );
  }

  1;
}

sub product_valid {
  my ($self, $coupon, $cart, $index) = @_;

  return $self->test_tier_matches($coupon, $cart, $index);
}

sub discount {
  my ($self, $coupon, $cart) = @_;

  return 0
    if $cart->total_cost < $self->{config}{min_cart};

  return $self->{config}{discount_dollars};
}

sub describe {
  my ($self) = @_;

  require BSE::Util::Format;

  sprintf("\$%s discount on cart over \$%s",
	  BSE::Util::Format::bse_number("money", $self->{config}{discount_dollars}),
	  BSE::Util::Format::bse_number("money", $self->{config}{min_cart}));
}

1;
