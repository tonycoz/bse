#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use CGI ':standard';
use Products;
use Product;
use Constants qw(:shop $TMPLDIR $CGI_URI);
use Squirrel::Template;
use Squirrel::ImageEditor;
use CGI::Cookie;
use BSE::Custom;
use BSE::Mail;
use BSE::Shop::Util qw/shop_cart_tags cart_item_opts nice_options total 
                       basic_tags load_order_fields need_logon/;
use BSE::Session;
use BSE::Cfg;
use Util qw/refresh_to/;

my $subject = $SHOP_MAIL_SUBJECT;

# our PGP passphrase
my $passphrase = $SHOP_PASSPHRASE;

# the class we use to perform encryption
# we can change this to switch between GnuPG and PGP
my $crypto_class = $SHOP_CRYPTO;

# id of the private key to use for signing
# leave as undef to use your default key
my $signing_id = $SHOP_SIGNING_ID;

# location of PGP
my $pgpe = $SHOP_PGPE;
my $pgp = $SHOP_PGP;
my $gpg = $SHOP_GPG;

my $from = $SHOP_FROM;

my $toName = $SHOP_TO_NAME;
my $toEmail= $SHOP_TO_EMAIL;

my $cfg = BSE::Cfg->new();
my $urlbase = $cfg->entryVar('site', 'url');
my $securlbase = $cfg->entryVar('site', 'secureurl');
my %session;
BSE::Session->tie_it(\%session, $cfg);

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
   recheckout => sub { checkout('', 1); },
   confirm => \&checkout_confirm,
   recalc=>\&recalc,
   recalculate=>\&recalc,
   purchase=>\&purchase,
   prePurchase=>\&prePurchase,
  );

for my $key (keys %steps) {
  if (param($key) or param("$key.x")) {
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

  # collect the product options
  my @options = map scalar param($_), split /,/, $product->{options};
  grep(!defined, @options) 
    and return show_cart(); # invalid parameter
  my $options = join(",", @options);
  
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
  @cart = grep { $_->{productId} ne $addid || $_->{options} ne $options } 
    @cart;
  push(@cart, { productId => $addid, units => $quantity, 
		price=>$product->{retailPrice},
		options=>$options });

  $session{cart} = \@cart;
  show_cart();
}

sub show_cart {
  my @cart = @{$session{cart}};
  my @cart_prods = map { Products->getByPkey($_->{productId}) } @cart;
  my $item_index = -1;
  my @options;
  my $option_index;
  
  $session{custom} ||= {};
  my %custom_state = %{$session{custom}};

  BSE::Custom->enter_cart(\@cart, \@cart_prods, \%custom_state); 

  my %acts;
  %acts =
    (
     BSE::Custom->cart_actions(\%acts, \@cart, \@cart_prods, \%custom_state),
     shop_cart_tags(\%acts, \@cart, \@cart_prods, \%session, $CGI::Q),
     basic_tags(\%acts),
    );
  $session{custom} = \%custom_state;

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
  $session{custom} ||= {};
  my %custom_state = %{$session{custom}};
  BSE::Custom->recalc($CGI::Q, \@cart, [], \%custom_state);
  $session{custom} = \%custom_state;
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

  @cart or return show_cart();

  my @cart_prods = map { Products->getByPkey($_->{productId}) } @cart;

  if (my ($msg, $id) = need_logon($cfg, \@cart, \@cart_prods, \%session)) {
    refresh_logon($msg, $id);
    return;
  }

  my $user;
  if ($session{userid}) {
    require 'SiteUsers.pm';
    $user = SiteUsers->getBy(userId=>$session{userid});
  }

  $session{custom} ||= {};
  my %custom_state = %{$session{custom}};

  BSE::Custom->enter_cart(\@cart, \@cart_prods, \%custom_state); 

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     shop_cart_tags(\%acts, \@cart, \@cart_prods, \%session, $CGI::Q),
     basic_tags(\%acts),
     message => sub { $message },
     old => sub { CGI::escapeHTML($olddata ? param($_[0]) : 
		    $user && defined $user->{$_[0]} ? $user->{$_[0]} : '') },
     BSE::Custom->checkout_actions(\%acts, \@cart, \@cart_prods, \%custom_state, $CGI::Q),
    );
  $session{custom} = \%custom_state;

  page('checkout.tmpl', \%acts);
}

# displays the data entered by the user so they can either confirm the
# details or redisplay the checkout page
sub checkout_confirm {
  my %order;
  my $error;

  my @cart_prods;
  unless (load_order_fields(0, $CGI::Q, \%order, \%session, \@cart_prods,
                            \$error)) {
    return checkout($error, 1);
  }
  ++$session{changed};
  my @cart = @{$session{cart}};
  # display the confirmation page
  my %acts;
  %acts =
    (
     order => sub { CGI::escapeHTML($order{$_[0]}) },
     shop_cart_tags(\%acts, \@cart, \@cart_prods, \%session, $CGI::Q),
     basic_tags(\%acts),
     old => 
     sub { 
       my $value = param($_[0]);
       defined $value or $value = '';
       CGI::escapeHTML($value);
     },
    );
  page('checkoutconfirm.tmpl', \%acts);
}

# this can be used instead of the purchase page to work in 2 steps:
#  - collect shipping details
#  - collect CC details
# the collection of the CC details should go to another script that 
# processes the CC information and then displays the order complete
# information
# BUG!!: this duplicates the code in purchase() a great deal
sub prePurchase {
  my @required = BSE::Custom->required_fields($CGI::Q, $session{custom});
  for my $field (@required) {
    defined(param($field)) && length(param($field))
      or return checkout("Field $field is required", 1);
  }
  if (grep /email/, @required) {
    defined(param('email')) && param('email') =~ /.\@./
      or return checkout("Please enter a valid email address", 1);
  }
  
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

  if (my ($msg, $id) = need_logon($cfg, \@cart, \@products, \%session)) {
    refresh_logon($msg, $id);
    return;
  }

  $order{total} += BSE::Custom->total_extras(\@cart, \@products, 
					     $session{custom});
  ++$session{changed};
  # blank anything else
  for my $column (@columns) {
    defined $order{$column} or $order{$column} = '';
  }
  # make sure the user can't set these behind our backs
  $order{filled} = 0;
  $order{paidFor} = 0;
  
  # this should be hard to guess
  $order{randomId} = md5_hex(time().rand().{}.$$);

  # check if a customizer has anything to do
  eval {
    BSE::Custom->order_save($CGI::Q, \%order, \@cart, \@products, $session{custom});
    ++$session{changed};
  };
  if ($@) {
    return checkout($@, 1);
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
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     iterate_items_reset => sub { $item_index = -1; },
     iterate_items => 
     sub { 
       if (++$item_index < @items) {
	 $option_index = -1;
	 @options = cart_item_opts($items[$item_index], 
				   $products[$item_index]);
	 return 1;
       }
       return 0;
     },
     item=> sub { CGI::escapeHTML($items[$item_index]{$_[0]}); },
     product => sub { CGI::escapeHTML($products[$item_index]{$_[0]}) },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $items[$item_index]{units} * $items[$item_index]{$what};
     },
     order => sub { CGI::escapeHTML($order->{$_[0]}) },
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0], 2;
       $acts{$func} || return "<: money $_[0] :>";
       return sprintf("%.02f", $acts{$func}->($args)/100);
     },
     old => sub { '' },
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
     iterate_options_reset => sub { $option_index = -1 },
     iterate_options => sub { ++$option_index < @options },
     option => sub { CGI::escapeHTML($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
    );
  # this should be reset once the order has been paid
  $session{orderPayment} = $order->{id};
  
  page('checkoutcard.tmpl', \%acts);
}

# the real work
sub purchase {
  # some basic validation, in case the user switched off javascript
  my @required = 
    (BSE::Custom->required_fields($CGI::Q, $session{custom}), 
     qw(cardHolder cardExpiry) );
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

  if (my ($msg, $id) = need_logon($cfg, \@cart, \@products, \%session)) {
    refresh_logon($msg, $id);
    return;
  }

  $order{orderDate} = $today;
  $order{total} += BSE::Custom->total_extras(\@cart, \@products, 
					     $session{custom});
  ++$session{changed};

  # blank anything else
  for my $column (@columns) {
    defined $order{$column} or $order{$column} = '';
  }
  # make sure the user can't set these behind our backs
  $order{filled} = 0;
  $order{paidFor} = 0;

  if ($session{userid}) {
    $order{userId} = $session{userid};
  }
  else {
    $order{userId} = '';
  }

  # this should be hard to guess
  $order{randomId} = md5_hex(time().rand().{}.$$);

  # check if a customizer has anything to do
  eval {
    BSE::Custom->order_save($CGI::Q, \%order, \@cart, \@products);
  };
  if ($@) {
    return checkout($@, 1);
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
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     BSE::Custom->purchase_actions(\%acts, \@items, \@products, 
				   $session{custom}),
     iterate_items_reset => sub { $item_index = -1; },
     iterate_items => 
     sub { 
       if (++$item_index < @items) {
	 $option_index = -1;
	 @options = cart_item_opts($items[$item_index], 
				   $products[$item_index]);
	 return 1;
       }
       return 0;
     },
     item=> sub { CGI::escapeHTML($items[$item_index]{$_[0]}); },
     product => sub { CGI::escapeHTML($products[$item_index]{$_[0]}) },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $items[$item_index]{units} * $items[$item_index]{$what};
     },
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
     iterate_options_reset => sub { $option_index = -1 },
     iterate_options => sub { ++$option_index < @options },
     option => sub { CGI::escapeHTML($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
    );
  send_order($order, \@items, \@products);
  $session{cart} = []; # empty the cart
  page('checkoutfinal.tmpl', \%acts);
}

# sends the email order confirmation and the PGP encrypted
# email to the site owner
sub send_order {
  my ($order, $items, $products) = @_;

  my %extras = $cfg->entriesCS('extra tags');
  for my $key (keys %extras) {
    # follow any links
    my $data = $cfg->entryVar('extra tags', $key);
    $extras{$key} = sub { $data };
  }

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     %extras,

     iterate_items_reset => sub { $item_index = -1; },
     iterate_items => 
     sub { 
       if (++$item_index < @$items) {
	 $option_index = -1;
	 @options = cart_item_opts($items->[$item_index], 
				   $products->[$item_index]);
	 return 1;
       }
       return 0;
     },
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
     iterate_options_reset => sub { $option_index = -1 },
     iterate_options => sub { ++$option_index < @options },
     option => sub { CGI::escapeHTML($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
    );
  my $templ = Squirrel::Template->new;

  my $mailer = BSE::Mail->new(cfg=>$cfg);
  # ok, send some email
  my $confirm = $templ->show_page($TMPLDIR, 'mailconfirm.tmpl', \%acts);
  if ($SHOP_EMAIL_ORDER) {
    $acts{cardNumber} = sub { param('cardNumber') };
    $acts{cardExpiry} = sub { param('cardExpiry') };
    my $ordertext = $templ->show_page($TMPLDIR, 'mailorder.tmpl', \%acts);

    eval "use $crypto_class";
    !$@ or die $@;
    my $encrypter = $crypto_class->new;

    my $debug = $cfg->entryBool('debug', 'mail_encryption', 0);
    my $sign = $cfg->entryBool('basic', 'sign', 1);

    # encrypt and sign
    my %opts = 
      (
       sign=> $sign,
       passphrase=> $passphrase,
       stripwarn=>1,
       debug=>$debug,
      );
    
    $opts{secretkeyid} = $signing_id if $signing_id;
    $opts{pgp} = $pgp if $pgp;
    $opts{gpg} = $gpg if $gpg;
    $opts{pgpe} = $pgpe if $pgpe;
    my $recip = "$toName $toEmail";

    my $crypted = $encrypter->encrypt($recip, $ordertext, %opts )
      or die "Cannot encrypt ", $encrypter->error;

    $mailer->send(to=>$toEmail, from=>$from, subject=>'New Order '.$order->{id},
		  body=>$crypted)
      or print STDERR "Error sending order to admin: ",$mailer->errstr,"\n";
  }
  $mailer->send(to=>$order->{emailAddress}, from=>$from,
		subject=>$subject . " " . localtime,
		body=>$confirm)
    or print STDERR "Error sending order to customer: ",$mailer->errstr,"\n";
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

sub refresh_logon {
  my ($msg, $msgid) = @_;
  my $url = $securlbase."/cgi-bin/user.pl";
  my %parms;
  $parms{r} = $securlbase."/cgi-bin/shop.pl?checkout=1";
  $parms{message} = $msg if $msg;
  $parms{mid} = $msgid if $msgid;
  $url .= "?" . join("&", map "$_=".CGI::escape($parms{$_}), keys %parms);
  
  refresh_to($url);
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
