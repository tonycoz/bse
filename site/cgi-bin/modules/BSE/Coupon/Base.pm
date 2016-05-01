package BSE::Coupon::Base;
use strict;

our $VERSION = "1.001";

sub new {
  my ($class, $config) = @_;

  return bless { config => $config }, $class;
}

sub config_rules {
  return {};
}

sub used_in {
  # do nothing by default
}

sub cart_wide {
  1;
}

sub product_valid {
  0;
}

sub product_discount {
  0;
}

sub product_discount_units {
  0;
}

sub test_all_tiers_match {
  my ($self, $coupon, $cart) = @_;

  my %tiers = map { $_ => 1 } $coupon->tiers;

  my $bad_tier_count = 0;
  for my $item ($cart->items) {
    if ($item->tier_id) {
      if (!$tiers{$item->tier_id}) {
	return 0;
      }
    }
    else {
      if (!$coupon->untiered) {
	return 0;
      }
    }
  }

  return 1;
}

sub test_tier_matches {
  my ($self, $coupon, $cart, $index) = @_;

  my @items = $cart->items;
  $index >= 0 && $index < @items
    or return 0;

  my $item = $items[$index];

  if ($item->tier_id) {
    my %tiers = map { $_ => 1 } $coupon->tiers;

    if (!$tiers{$item->tier_id}) {
      return 0;
    }
  }
  else {
    if (!$coupon->untiered) {
      return 0;
    }
  }

  return 1;
}

1;

__END__

=head1 NAME

BSE::Coupon::Base - base class for coupon behaviour classes.

=head1 SYNOPSIS

  package BSE::Coupon::YourCoupon;
  use parent 'BSE::Coupon::Base';

  sub new {
    my ($class, $config) = @_;
    ...
  }

  # ... and more

=head1 DESCRIPTION

This class provides base behaviour and documentation on the
requirements of BSE coupon behaviour classes.

A coupon behaviour class must use BSE::Coupon::Base as a base class,
to provide default behaviour that might be added later to this
specification.

A coupon behaviour class may override the default constructor:

=over

=item *

new($config) - create a new coupon behaviour object.  This is passed a
single parameter of the config hash for that behaviour, as specified
by config_fields().

=back

The class must implement the following class methods:

=over

=item *

config_fields() - returns a hash reference of customization
fields for this coupon class.  For example it might return a field
definition for the dollar amount to be discounted.

If a field called C<discount_percent> is included it will be stored in
the C<discount_percent> field of the coupon entry.

  my $fields = $class->config_fields();

=item *

config_rules() - any extra rule definitions required for the
validation rules in config_fields().

  my $rules = $class->config_rules();

A default implementation is provided that returns an empty hash.

=item *

config_valid() - validate whether a supplied configuration is valid.

  my $valid = $class->config_valid($config, \%errors);

This occurs in addition to any validation rules in the fields returned
by config_fields().

=item *

class_description() - a brief description of this coupon behaviour,
for use in drop-down lists when creating a coupon.

=back

The class must implement the following object methods:

=over

=item *

is_active() - return true if the coupon is usable for the cart.  If
the coupon is not usable, returns $msg as the reson why:

  my ($active, $msg) = $cb->is_active($coupon, $cart);

This is in addition to the date and tier checks already done for the coupon.

=item *

discount() - return the discount in cents provided by the coupon on
the supplied cart.

  my ($cents) = $cb->discount($coupon, $cart);

Must only be called if is_active() returns true for the cart.

=item *

product_valid($coupon, $cart, $index) - returns true if the given line
item in the cart is valid for the coupon.

Only meaningful for cart-wide coupons.

=item *

product_discount($coupon, $cart, $index) - returns the per-unit
discount in cents provided by the coupon on the specified entry in the
given cart.

  my ($cents) = $cb->product_discount($coupon, $cart, $index);

Must only be called if is_active() returns true for the cart.

Returns 0 if the discount is against the entire cart.

A default implementation returns 0.

=item *

product_discount_units($coupon, $cart, $index) - returns the number of
units the product specific discount applies to on specified entry in
the given cart.

  my ($cents) = $cb->product_discount_units($coupon, $cart, $index);

Must only be called if is_active() returns true for the cart.

Returns 0 if the discount is against the entire cart.

A default implementation returns 0.

=item *

cart_wide($coupon, $cart) - return true if the coupon behaviour
provides a cart-wide discount.  Generally this is class-wide, but must
be called as an instance method in-case that's untrue for some
particular behaviour class.

The default implementation returns false.

=item *

used_in() - called when a new order if finalized with the given coupon
code.

  $cb->used_in($coupon_code, $order);

A default implementation is provided that does nothing.

=item *

describe() - return a text description of the coupon based on its
configuration data.

  my ($text) = $cb->describe();

=back

