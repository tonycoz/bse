#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use CGI ':standard';
use BSE::Request;
use BSE::UI::Shop;
use BSE::Template;
use Carp 'confess';

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;
my $result = BSE::UI::Shop->dispatch($req);
BSE::Template->output_result($req, $result);

__END__

=head1 NAME

shop.pl - implements the shop for BSE

=head1 DESCRIPTION

shop.pl implements the shop for BSE.

=head1 TAGS

=head2 Cart page

=over 4

=item iterator ... items

Iterates over the items in the shopping cart, setting the C<item> tag
for each one.

=item item I<field>

Retreives the given field from the item.  This can include product
fields for this item.

=item index

The numeric index of the current item.

=item extended [<field>]

The "extended price", the product of the unit cost and the number of
units for the current item in the cart.  I<field> defaults to the
price of the product.

=item money I<which> <field>

Formats the given field as a money value (without a currency symbol.)

=item count

The number of items in the cart.

=item ifUser

Conditional tag, true if a registered user is logged in.

=item user I<field>

Retrieved the given field from the currently logged in user, if any.

=back

=head2 Checkout tags

This has the same tags as the L<Cart page>, and some extras:

=over 4

=item total

The total cost of all items in the cart.

This will need to be formatted as a money value with the C<money> tag.

=item message

An error message, if a validation error occurred.

=item old I<field>

The previously entered value for I<field>.  This should be used as the
value for the various checkout fields, so that if a validation error
occurs the user won't need to re-enter values.

=back

=head2 Completed order

These tags are used in the F<checkoutfinal_base.tmpl>.

=over 4

=item item I<field>

=item product I<field>

This is split out for these forms.

=item order I<field>

Order fields.

=item ifSubscribingTo I<subid>

Can be used to check if this order is intended to be subscribing to a
subscription.

=back

You can also use "|format" at the end of a field to perform some
simple formatting.  Eg. <:order total |m6:> or <:order id |%06d:>.

=over 4

=item m<number>

Formats the value as a <number> wide money value.

=item %<format>

Performs sprintf() formatting on the value.  Eg. %06d will format 25
as 000025.

=back

=head2 Mailed order tags

These tags are used in the emails sent to the user to confirm an order
and in the encrypted copy sent to the site administrator:

=over 4

=item iterate ... items

Iterates over the items in the order.

=item item I<field>

Access to the given field in the order item.

=item product I<field>

Access to the product field for the current order item.

=item order I<field>

Access to fields of the order.

=item extended I<field>

The product of the I<field> in the current item and it's quantity.

=item money I<tag> I<parameters>

Formats the given field as a money value.

=back

The mail generation template can use extra formatting specified with
'|format':

=over 4

=item m<number>

Format the value as a I<number> wide money value.

=item %<format>

Performs sprintf formatting on the value.

=item <number>

Left justifies the value in a I<number> wide field.

=back

The order email sent to the site administrator has a couple of extra
fields:

=over 4

=item cardNumber

The credit card number of the user's credit card.

=item cardExpiry

The entered expiry date for the user's credit card.

=back

=head2 Order fields

These names can be used with the <: order ... :> tag.

Monetary values should typically be used with <:money order ...:>

=over 4

=item id

The order id or order number.

=item delivFirstName

=item delivLastName

=item delivStreet

=item delivSuburb

=item delivState

=item delivPostCode

=item delivCountry

Delivery information for the order.

=item billFirstName

=item billLastName

=item billStreet

=item billSuburb

=item billState

=item billPostCode

=item billCountry

Billing information for the order.

=item telephone

=item facsimile

=item emailAddress

Contact information for the order.

=item total

Total price of the order.

=item wholesaleTotal

Wholesale cost of the total.  Your costs, if you entered wholesale
prices for the products.

=item gst

GST (in Australia) payable on the order, if you entered GST for the products.

=item orderDate

When the order was made.

=item filled

Whether or not the order has been filled.  This can be used with the
order_filled target in shopadmin.pl for tracking filled orders.

=item whenFilled

The time and date when the order was filled.

=item whoFilled

The user who marked the order as filled.

=item paidFor

Whether or not the order has been paid for.  This can be used with a
custom purchasing handler to mark the product as paid for.  You can
then filter the order list to only display paid for orders.

=item paymentReceipt

A custom payment handler can fill this with receipt information.

=item randomId

Generated by the prePurchase target, this can be used as a difficult
to guess identifier for orders, when working with custom payment
handlers.

=item cancelled

This can be used by a custom payment handler to mark an order as
cancelled if the user starts processing an order without completing
payment.

=back

=head2 Order item fields

=over 4

=item productId

The product id of this item.

=item orderId 

The order Id.

=item units

The number of units for this item.

=item price

The price paid for the product.

=item wholesalePrice

The wholesale price for the product.

=item gst

The gst for the product.

=item options

A comma separated list of options specified for this item.  These
correspond to the option names in the product.

=back

=head2 Options

New with 0.10_04 is the facility to set options for each product.

The cart, checkout and checkoutfinal pages now include the following
tags:

=over

=item iterator ... options

within an item, iterates over the options for this item in the cart.
Sets the item tag.

=item option field

Retrieves the given field from the option, possible field names are:

=over

=item id

The type/identifier for this option.  eg. msize for a male clothing
size field.

=item value

The underlying value of the option, eg. XL.

=item desc

The description of the field from the product options hash.  If the
description isn't defined this is the same as the id. eg. Size.

=item label

The description of the value from the product options hash.
eg. "Extra large".

=back

=item ifOptions

A conditional tag, true if the current cart item has any options.

=item options

A simple rendering of the options as a parenthesized comma-separated
list.

=back

=cut
