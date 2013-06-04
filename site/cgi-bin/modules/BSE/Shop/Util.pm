package BSE::Shop::Util;
use strict;
use vars qw(@ISA @EXPORT_OK);
@ISA = qw/Exporter/;
@EXPORT_OK = qw/shop_cart_tags cart_item_opts nice_options shop_nice_options
                total shop_total load_order_fields basic_tags
                payment_types order_item_opts
 PAYMENT_CC PAYMENT_CHEQUE PAYMENT_CALLME PAYMENT_MANUAL PAYMENT_PAYPAL/;

our $VERSION = "1.008";

our %EXPORT_TAGS =
  (
   payment => [ grep /^PAYMENT_/, @EXPORT_OK ],
  );

use Constants qw/:shop/;
use BSE::Util::SQL qw(now_sqldate);
use BSE::Util::Tags qw(tag_article);
use BSE::CfgInfo qw(custom_class);
use Carp 'confess';
use BSE::Util::HTML qw(escape_html);
use BSE::Shop::PaymentTypes qw(:default payment_types);
use BSE::Util::Iterate;

=item shop_cart_tags($cart, $stage)

Returns a list of tags which display the cart details

Returns standard dynamic tags and:

=over

=item *

ifHaveSaleFiles - returns true if any of the supplied products has a
file attached that's forSale.

=item *

And several more undocumented DOCME.

=back

=cut

sub shop_cart_tags {
  my ($acts, $cart, $req, $stage) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;
  $cfg or confess "No config";
  $cfg->isa("BSE::Cfg") or confess "Not a config";

  my $location;
  my $current_item;
  my $ito = BSE::Util::Iterate::Objects->new;
  return
    (
     $req->dyn_user_tags(),
     $ito->make
     (
      plural => "items",
      single => "item",
      code => sub { @{$cart->items} },
      store => \$current_item,
     ),
     count => scalar(@{$cart->items}),
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $current_item->extended($what);
     },
     total => sub { $cart->total_cost },
     $ito->make
     (
      plural => "options",
      single => "option",
     ),
     options => sub { $current_item->option_text },
     session => [ \&tag_session, \$current_item ],
     location => [ \&tag_location, \$current_item, \$location ],
     ifHaveSaleFiles => [ have_sales_files => $cart ],
     custom_class($cfg)
     ->checkout_actions($acts, $cart->items, $cart->products, $req->session->{custom}, $q, $cfg),
    );  
}

sub tag_session {
  my ($ritem, $arg) = @_;

  $$ritem or return '';

  $$ritem->{session_id} or return '';

  my $session = $$ritem->session;
  my $value = $session->{$arg};
  defined $value or return '';

  escape_html($value);
}

sub tag_location {
  my ($ritem, $rlocation, $arg) = @_;

  $$ritem or return '';

  $$ritem->{session_id} or return '';

  unless ($$rlocation) {
    require BSE::TB::Locations;
    ($$rlocation) = BSE::TB::Locations->getSpecial(session_id => $$ritem->{session_id})
      or return '';
  }

  my $value = $$rlocation->{$arg};
  defined $value or return '';

  escape_html($value);
}

sub tag_ifHaveSaleFiles {
  my ($rhave_sale_files, $cart_prods) = @_;

  unless (defined $$rhave_sale_files) {
    $$rhave_sale_files = 0;
  PRODUCT:
    for my $prod (@$cart_prods) {
      if ($prod->has_sale_files) {
	$$rhave_sale_files = 1;
	last PRODUCT;
      }
    }
  }

  return $$rhave_sale_files;
}

sub cart_item_opts {
  my ($req, $cart_item, $product) = @_;

  my @option_descs = $product->option_descs($req->cfg, $cart_item->{options});

  my @options;
  my $index = 0;
  for my $option (@option_descs) {
    my $out_opt =
      {
       id => $option->{name},
       value => $option->{value},
       desc => $option->{desc},
       label => $option->{display}
      };

    push @options, $out_opt;
    ++$index;
  }
  
  return @options;
}

sub order_item_opts {
  my ($req, $order_item, $product) = @_;

  return $order_item->option_hashes;
}

sub nice_options {
  my (@options) = @_;

  if (@options) {
    return '('.join(", ", map("$_->{desc} $_->{label}", @options)).')';
  }
  else {
    return '';
  }
}

*shop_nice_options = \&nice_options;

sub total {
  my ($cart, $products, $state, $cfg, $stage) = @_;

  my $total = 0;
  for my $item (@$cart) {
    $total += $item->{units} * $item->{price};
  }
  $total += custom_class($cfg)
    ->total_extras($cart, $products, $state, $cfg, $stage);

  return $total;
}

*shop_total = \&total;

# paranoia, don't store these
my %nostore =
  (
   cardNumber => 1,
   cardExpiry => 1,
  );

sub load_order_fields {
  my ($wantcard, $q, $order, $req, $cart_prods, $error) = @_;

  my $session = $req->session;
  my $cfg = $req->cfg;

  my $cust_class = custom_class($cfg);

  my @required = $cust_class->required_fields($q, $session->{custom});
  push(@required, qw(ccName cardExpiry)) if $wantcard;
  for my $field (@required) {
    defined($q->param($field)) && length($q->param($field))
      or do { $$error = "Field $field is required"; return 0 };
  }
  if (grep /email/, @required) {
    defined($q->param('email')) && $q->param('email') =~ /.\@./
      or do { $$error = "Please enter a valid email address"; return 0 };
  }

  if ($wantcard) {
    defined($q->param('cardNumber')) && $q->param('cardNumber') =~ /^\d+$/
      or do { $$error = "Please enter a credit card number"; return 0 };
  }

  my @cart = @{$session->{cart}};
  @cart or 
    do { $$error = 'You have no items in your shopping cart'; return 0 };

  require BSE::TB::Orders;
  require BSE::TB::OrderItems;

  my %order;
  # so we can quickly check for columns
  my @columns = BSE::TB::Order->columns;
  my %columns; 
  @columns{@columns} = @columns;

  for my $field ($q->param()) {
    $order->{$field} = $q->param($field)
      unless $nostore{$field};
  }

  my $ccNumber = $q->param('cardNumber');
  my $ccExpiry = $q->param('cardExpiry');

  use Digest::MD5 'md5_hex';
  $ccNumber =~ tr/0-9//cd;
  $order->{ccNumberHash} = md5_hex($ccNumber);
  $order->{ccExpiryHash} = md5_hex($ccExpiry);

  # work out totals
  $order->{total} = 0;
  $order->{gst} = 0;
  $order->{wholesale} = 0;
  my @products;
  my $today = now_sqldate();
  for my $item (@cart) {
    my $product = Products->getByPkey($item->{productId});
    # double check that it's still a valid product
    if (!$product) {
      $$error = "Product $item->{productId} not found";
      return 0;
    }
    elsif ($product->{release} gt $today || $product->{expire} lt $today
	   || !$product->{listed}) {
      $$error = "Sorry, '$product->{title}' is no longer available";
      return 0;
    }
    push(@products, $product); # used in page rendering
    @$item{qw/price wholesalePrice gst/} = 
      @$product{qw/retailPrice wholesalePrice gst/};
    $order->{total} += $item->{price} * $item->{units};
    $order->{wholesale} += $item->{wholesalePrice} * $item->{units};
    $order->{gst} += $item->{gst} * $item->{units};
  }
  $order->{orderDate} = $today;
  $order->{total} += $cust_class->total_extras(\@cart, \@products, 
					     $session->{custom});

  if (need_logon($req, \@cart, \@products)) {
    $$error = "Your cart contains some file-based products.  Please register or logon";
    return 0;
  }


  # blank anything else
  for my $column (@columns) {
    defined $order->{$column} or $order->{$column} = '';
  }
  # make sure the user can't set these behind our backs
  $order->{filled} = 0;
  $order->{paidFor} = 0;

  # this should be hard to guess
  $order->{randomId} = md5_hex(time().rand().{}.$$);

  # check if a customizer has anything to do
  eval {
    $cust_class->order_save($q, $order, \@cart, \@products, $session->{custom});
  };
  if ($@) {
    $$error = $@;
    return 0;
  }

  @$cart_prods = @products if $cart_prods;

  return 1;
}

sub basic_tags {
  my ($acts) = @_;

  return 
    (
#       money =>
#       sub {
#         my ($func, $args) = split ' ', $_[0], 2;
#         $acts->{$func} || return "<: money $_[0] :>";
#         return sprintf("%.02f", $acts->{$func}->($args)/100);
#       },
    );
}

1;
