package BSE::CustomBase;
use strict;

sub enter_cart {
  my ($class, $items, $products, $state) = @_;

  return 1;
}

sub cart_actions {
  my ($class, $acts, $items, $products, $state) = @_;

  return ();
}

sub checkout_actions {
  my ($class, $acts, $items, $products) = @_;

  return ();
}

sub order_save {
  my ($class, $cgi, $order, $items) = @_;

  return 1;
}

sub total_extras {
  my ($class, $cart,$state) = @_;

  0;
}

sub recalc {
  my ($class, $q, $items, $products, $state) = @_;
}

sub required_fields {
  my ($class, $q, $state) = @_;

  qw(name1 name2 address city postcode state country);
}

sub purchase_actions {
  my ($class, $acts, $items, $products, $state) = @_;

  return;
}

1;

=head1 NAME

  BSE::CustomBase - base class for the customization class.

=head1 SYNOPSIS

  package BSE::Custom;
  use base 'BSE::CustomBase';

  ... implement overridden functions ...

=head1 DESCRIPTION

This class provides basic implementations of various methods of
BSE::Custom.

The aim is that if extra customization methods are created, you can
upgrade everything but BSE::Custom, and your code will still work.

Current methods that can be implemented in BSE::Custom are:

=over

=item checkout_actions($acts, $items, $products, $state, $cgi)

Return a list of extra "actions" or members of the %acts hash used for
converting the checkout template to the final output.  Used to define
extra tags for the checkout page.

=item order_save($cgi, $order, $items)

Called immediately before the order is saved.  You can perform extra
validation and die() with an error message describing the problem, or
perform extra data manipulation.

=item BSE::Custom->enter_cart($q, $items, $products, $state)

Called just before the cart is displayed.

=item BSE::Custom->cart_actions($acts, $items, $products, $state)

Defines tags available in the cart.

=item BSE::Custom->total_extras($item, $products, $state)

Extras that should be added to the total.  You should probably define
extra tags in cart_actions() and purchase_actions() to display the
extra data.

=item BSE::Custom->recalc($q, $items, $products, $state)

Called when a recalc is done.  Useful for storing form values into the
state.

=item BSE::Custom->required_field($q, $state)

Called to get the fields required for checkout.  You might want to add
or remove them, depending on the products bought.

=item BSE::Custom->purchase_actions($acts, $items, $products, $state)

Defines extra tags for use on the checkout page.

=back

=cut
