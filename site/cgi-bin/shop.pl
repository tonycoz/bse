#!/usr/bin/perl -w
use strict;
use lib 'modules';
use CGI ':standard';
use CGI::Carp 'fatalsToBrowser';
use Products;
use Product;
use Constants qw(:shop $TMPLDIR %EXTRA_TAGS $CGI_URI);
use Squirrel::Template;
use Apache::Session;
use Squirrel::ImageEditor;
use CGI::Cookie;
use Apache::Session::MySQL;

my $subject = $SHOP_MAIL_SUBJECT;

# our PGP passphrase
my $passphrase = $SHOP_PASSPHRASE;

# the class we use to perform encryption
# we can change this to switch between GnuPG and PGP
my $crypto_class = $SHOP_CRYPTO;

# id of the private key to use for signing
# leave as undef to use your default key
my $signing_id = $SHOP_SIGNING_ID;

# location of sendmail
my $sendmail = $SHOP_SENDMAIL;

# location of PGP
my $pgpe = $SHOP_PGPE;
my $pgp = $SHOP_PGP;
my $gpg = $SHOP_GPG;

my $from = $SHOP_FROM;

my $toName = $SHOP_TO_NAME;
my $toEmail= $SHOP_TO_EMAIL;

#my $opts = '-t -odi';
my $opts = '-t';

# Lifetime (in hours _OR_ minutes) of the shopping cart cookie.
# Value can be in minutes (append an 'm') or hours (append an 'h').
my $lifetime = '+3h';
my $path = $CGI_URI . '/';

# maximum age of shopping cart cookie
my $max_cookie_age = "+3h";

my %cookies = fetch CGI::Cookie;
my $sessionid;
$sessionid = $cookies{sessionid}->value if exists $cookies{sessionid};
my %session;

my $dh = single DatabaseHandle;
eval {
  tie %session, 'Apache::Session::MySQL', $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
};
if ($@ && $@ =~ /Object does not exist/) {
  # try again
  undef $sessionid;
  tie %session, 'Apache::Session::MySQL', $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
}
unless ($sessionid) {
  # save the new sessionid
  print "Set-Cookie: ",
    CGI::Cookie->new(-name=>'sessionid', -value=>$session{_session_id}, 
		     -expires=>$lifetime),"\n";
}

# this shouldn't be necessary, but it stopped working elsewhere and this
# fixed it
END {
  untie %session;
}

if (!exists $session{cart}) {
  $session{cart} = [];
}

# the keys here are the names of the buttons on the various forms
# we also have 'delete_<number>' buttons.
my %steps =
  (
   add=>\&add_item,
   cart=>\&show_cart,
   checkout=>\&checkout,
   recalc=>\&recalc,
   purchase=>\&purchase,
  );

for my $key (keys %steps) {
  if (param($key)) {
    $steps{$key}->();
    exit;
  }
}

for my $key (param()) {
  if ($key =~ /^delete_(\d+)/) {
    remove_item($1);
    exit;
  }
}

show_cart();

sub add_item {
  my $addid = param('id');
  my $quantity = param('quantity');
  my $product;
  $product = Products->getByPkey($addid) if $addid;
  $product or return show_cart(); # oops
  
  # the product must be non-expired and listed
  my $today = epoch_to_sql(time);
  $product->{release} le $today and $today le $product->{expire}
    or return show_cart();
  $product->{listed} or return show_cart();

  # we need a natural integer quantity
  $quantity =~ /^\d+$/
    or return show_cart();

  my @cart = @{$session{cart}};
 
  # if this is is already present, replace it
  @cart = grep { $_->{productId} ne $addid } @cart;
  push(@cart, { productId => $addid, units => $quantity, 
		price=>$product->{retailPrice} });
  $session{cart} = \@cart;
  show_cart();
}

sub total {
  my ($cart) = @_;

  my $total = 0;
  for my $item (@$cart) {
    $total += $item->{units} * $item->{price};
  }

  return $total;
}

sub show_cart {
  my @cart = @{$session{cart}};
  my @cart_prods = map { Products->getByPkey($_->{productId}) } @cart;
  my $item_index = -1;

  my %acts;
  %acts =
    (
     iterate_items => sub { ++$item_index < @cart },
     item => 
     sub { $cart[$item_index]{$_[0]} || $cart_prods[$item_index]{$_[0]} },
     index => sub { $item_index },
     total => sub { total(\@cart) },
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0], 2;
       $acts{$func} || return "<: money $_[0] :>";
       return sprintf("%.02f", $acts{$func}->($args)/100);
     },
     count => sub { scalar @cart },
    );
  page('cart.tmpl', \%acts);
}

sub update_quantities {
  my @cart = @{$session{cart}};
  for my $index (0..$#cart) {
    my $new_quantity = param("quantity_$index");
    if (defined $new_quantity) {
      if ($new_quantity =~ /^\s*(\d+)/) {
	$cart[$index]{units} = $1;
      }
      elsif ($new_quantity =~ /^\s*$/) {
	$cart[$index]{units} = 0;
      }
    }
    
  }
  @cart = grep { $_->{units} != 0 } @cart;
  $session{cart} = \@cart;
}

sub recalc {
  update_quantities();
  show_cart();
}

sub remove_item {
  my ($index) = @_;
  my @cart = @{$session{cart}};
  if ($index >= 0 && $index < @cart) {
    splice(@cart, $index, 1);
  }
  $session{cart} = \@cart;

  print "Refresh: 0; url=\"$ENV{SCRIPT_NAME}\"\n";
  print "Content-Type: text/html\n\n<html> </html>\n";
}

# display the checkout form
# can also be called with an error message and a flag to fillin the old
# values for the form elements
sub checkout {
  my ($message, $olddata) = @_;

  $message = '' unless defined $message;

  update_quantities();
  my @cart = @{$session{cart}};
  my @cart_prods = map { Products->getByPkey($_->{productId}) } @cart;
  my $item_index = -1;
  my %acts;
  %acts =
    (
     iterate_items => sub { ++$item_index < @cart },
     item => 
     sub { $cart[$item_index]{$_[0]} || $cart_prods[$item_index]{$_[0]} },
     index => sub { $item_index },
     total => sub { total(\@cart) },
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0], 2;
       $acts{$func} || return "<: money $_[0] :>";
       return sprintf("%.02f", $acts{$func}->($args)/100);
     },
     count => sub { scalar @cart },
     message => sub { $message },
     old => sub { $olddata ? param($_[0]) : '' },
    );

  page('checkout.tmpl', \%acts);
}

# the real work
sub purchase {
  # some basic validation, in case the user switched off javascript
  my @required = 
    qw(name1 name2 address city postcode state country cardHolder cardExpiry);
  for my $field (@required) {
    defined(param($field)) && length(param($field))
      or return checkout("Field $field is required", 1);
  }
  defined(param('email')) && param('email') =~ /.\@./
    or return checkout("Please enter a valid email address", 1);
  defined(param('cardNumber')) && param('cardNumber') =~ /^\d+$/
    or return checkout("Please enter a credit card number", 1);

  use Orders;
  use Order;
  use OrderItems;
  use OrderItem;

  # map some form fields to order field names
  my %field_map = 
    (
     name1 => 'delivFirstName',
     name2 => 'delivLastName',
     address => 'delivStreet',
     city => 'delivSuburb',
     postcode => 'delivPostCode',
     state => 'delivState',
     country => 'delivCountry',
     email => 'emailAddress',
     cardHolder => 'ccName',
     cardType => 'ccType',
    );
  # paranoia, don't store these
  my %nostore =
    (
     cardNumber => 1,
     cardExpiry => 1,
    );
  my %order;
  my @cart = @{$session{cart}};
  @cart or return show_cart('You have no items in your shopping cart');

  # so we can quickly check for columns
  my @columns = Order->columns;
  my %columns; 
  @columns{@columns} = @columns;

  for my $field (param()) {
    $order{$field_map{$field} || $field} = param($field)
      unless $nostore{$field};
  }

  my $ccNumber = param('cardNumber');
  my $ccExpiry = param('cardExpiry');

  use Digest::MD5 'md5_hex';
  $ccNumber =~ tr/0-9//cd;
  $order{ccNumberHash} = md5_hex($ccNumber);
  $order{ccExpiryHash} = md5_hex($ccExpiry);

  # work out totals
  $order{total} = 0;
  $order{gst} = 0;
  $order{wholesale} = 0;
  my @products;
  my $today = epoch_to_sql(time);
  for my $item (@cart) {
    my $product = Products->getByPkey($item->{productId});
    # double check that it's still a valid product
    if (!$product) {
      return show_cart("Product $item->{productId} not found");
    }
    elsif ($product->{release} gt $today || $product->{expire} lt $today
	   || !$product->{listed}) {
      return show_cart("Sorry, '$product->{title}' is no longer available");
    }
    push(@products, $product); # used in page rendering
    @$item{qw/price wholesalePrice gst/} = 
      @$product{qw/retailPrice wholesalePrice gst/};
    $order{total} += $item->{price} * $item->{units};
    $order{wholesale} += $item->{wholesalePrice} * $item->{units};
    $order{gst} += $item->{gst} * $item->{units};
  }
  $order{orderDate} = $today;

  # blank anything else
  for my $column (@columns) {
    defined $order{$column} or $order{$column} = '';
  }

  # load up the database
  my @data = @order{@columns};
  shift @data; # lose the dummy id
  my $order = Orders->add(@data)
    or die "Cannot add order";
  my @items;
  my @item_cols = OrderItem->columns;
  for my $row (@cart) {
    $row->{orderId} = $order->{id};
    my @data = @$row{@item_cols};
    shift @data;
    push(@items, OrderItems->add(@data));
  }

  my $item_index = -1;
  my %acts;
  %acts =
    (
     iterate_items_reset => sub { $item_index = -1; },
     iterate_items => sub { ++$item_index < @items },
     item=> sub { CGI::escapeHTML($items[$item_index]{$_[0]}); },
     product => sub { CGI::escapeHTML($products[$item_index]{$_[0]}) },
     order => sub { CGI::escapeHTML($order->{$_[0]}) },
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0], 2;
       $acts{$func} || return "<: money $_[0] :>";
       return sprintf("%.02f", $acts{$func}->($args)/100);
     },
     _format =>
     sub {
       my ($value, $fmt) = @_;
       if ($fmt =~ /^m(\d+)/) {
	 return sprintf("%$1s", sprintf("%.2f", $value/100));
       }
       elsif ($fmt =~ /%/) {
	 return sprintf($fmt, $value);
       }
     },
    );
  send_order($order, \@items, \@products);
  $session{cart} = []; # empty the cart
  page('checkoutfinal.tmpl', \%acts);
}

# sends the email order confirmation and the PGP encrypted
# email to the site owner
sub send_order {
  my ($order, $items, $products) = @_;

  my %extras = %EXTRA_TAGS;
  for my $key (keys %extras) {
    unless (ref $extras{$key}) {
      my $data = $extras{$key};
      $extras{$key} = sub { $data };
    }
  }

  my $item_index = -1;
  my %acts;
  %acts =
    (
     %extras,

     iterate_items_reset => sub { $item_index = -1; },
     iterate_items => sub { return ++$item_index < @$items },
     item=> sub { $items->[$item_index]{$_[0]}; },
     product => sub { $products->[$item_index]{$_[0]} },
     order => sub { $order->{$_[0]} },
     extended => 
     sub {
       $items->[$item_index]{units} * $items->[$item_index]{$_[0]};
     },
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0], 2;
       $acts{$func} || return "<: money $_[0] :>";
       return sprintf("%.02f", $acts{$func}->($args)/100);
     },
     _format =>
     sub {
       my ($value, $fmt) = @_;
       if ($fmt =~ /^m(\d+)/) {
	 return sprintf("%$1s", sprintf("%.2f", $value/100));
       }
       elsif ($fmt =~ /%/) {
	 return sprintf($fmt, $value);
       }
       elsif ($fmt =~ /^\d+$/) {
	 return substr($value . (" " x $fmt), 0, $fmt);
       }
       else {
	 return $value;
       }
     },
    );
  my $templ = Squirrel::Template->new;

  # ok, send some email
  my $confirm = $templ->show_page($TMPLDIR, 'mailconfirm.tmpl', \%acts);
  if ($SHOP_EMAIL_ORDER) {
    $acts{cardNumber} = sub { param('cardNumber') };
    $acts{cardExpiry} = sub { param('cardExpiry') };
    my $ordertext = $templ->show_page($TMPLDIR, 'mailorder.tmpl', \%acts);

    eval "use $crypto_class";
    !$@ or die $@;
    my $encrypter = $crypto_class->new;

    # encrypt and sign
    my %opts = 
      (
       sign=> 1,
       passphrase=> $passphrase,
       stripwarn=>1,
       #debug=>1,
      );
    $opts{secretkeyid} = $signing_id if $signing_id;
    $opts{pgp} = $pgp if $pgp;
    $opts{gpg} = $gpg if $gpg;
    $opts{pgpe} = $pgpe if $pgpe;
    #$opts{home} = '/home/bodyscoop';
    my $recip = "$toName $toEmail";

    my $crypted = $encrypter->encrypt($recip, $ordertext, %opts )
      or die "Cannot encrypt ", $encrypter->error;

    sendmail($toEmail, 'New Order', $crypted, $from);
  }
  sendmail($order->{emailAddress}, $subject . " " . localtime, $confirm, $from);

}

sub sendmail {
  my ($recip, $subject, $body, $from) = @_;

  open MAIL, "| $sendmail $opts"
    or die "Cannot open pipe to sendmail: $!";
  print MAIL <<EOS;
From: $from
To: $recip
Subject: $subject

$body
EOS
  close MAIL;
}

sub page {
  my ($template, $acts) = @_;
  print "Content-Type: text/html\n\n";
  print Squirrel::Template->new->show_page($TMPLDIR, $template, $acts);
}

# convert an epoch time to sql format
sub epoch_to_sql {
  use POSIX 'strftime';
  my ($time) = @_;

  return strftime('%Y-%m-%d', localtime $time);
}

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

=item money I<which> <field>

Formats the given field as a money value (without a currency symbol.)

=item count

The number of items in the cart.

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

=back

=cut
