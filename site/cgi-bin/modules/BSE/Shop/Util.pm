package BSE::Shop::Util;
use strict;
use vars qw(@ISA @EXPORT_OK);
@ISA = qw/Exporter/;
@EXPORT_OK = qw/shop_cart_tags cart_item_opts nice_options shop_nice_options
                total shop_total load_order_fields basic_tags/;
use Constants qw/:shop/;
use BSE::Util::SQL qw(now_sqldate);
use BSE::Custom;

# returns a list of tags which display the cart details
sub shop_cart_tags {
  my ($acts, $cart, $cart_prods, $session, $q) = @_;

  my $item_index;
  my $option_index;
  my @options;
  return
    (
     iterate_items_reset => sub { $item_index = -1 },
     iterate_items => 
     sub { 
       if (++$item_index < @$cart) {
	 $option_index = -1;
	 @options = cart_item_opts($cart->[$item_index], 
				   $cart_prods->[$item_index]);
	 return 1;
       }
       return 0;
     },
     item => 
     sub { $cart->[$item_index]{$_[0]} || $cart_prods->[$item_index]{$_[0]} },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $cart->[$item_index]{units} * $cart_prods->[$item_index]{$what};
     },
     index => sub { $item_index },
     total => sub { total($cart, $cart_prods, $session->{custom}) },
     iterate_options_reset => sub { $option_index = -1 },
     iterate_options => sub { ++$option_index < @options },
     option => sub { CGI::escapeHTML($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
     BSE::Custom->checkout_actions($acts, $cart, $cart_prods, 
				   $session->{custom}, $q),
    );  
}

sub cart_item_opts {
  my ($cart_item, $product) = @_;

  my @options = ();
  my @values = split /,/, $cart_item->{options};
  my @ids = split /,/, $product->{options};
  for my $opt_index (0 .. $#ids) {
    my $entry = $SHOP_PRODUCT_OPTS{$ids[$opt_index]};
    my $option = {
		  id=>$ids[$opt_index],
		  value=>$values[$opt_index],
		  desc => $entry->{desc} || $ids[$opt_index],
		 };
    if ($entry->{labels}) {
      $option->{label} = $entry->{labels}{$values[$opt_index]};
    }
    else {
      $option->{label} = $option->{value};
    }
    push(@options, $option);
  }

  return @options;
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
  my ($cart, $products, $state) = @_;

  my $total = 0;
  for my $item (@$cart) {
    $total += $item->{units} * $item->{price};
  }
  $total += BSE::Custom->total_extras($cart, $products, $state);

  return $total;
}

*shop_total = \&total;

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

sub load_order_fields {
  my ($wantcard, $q, $order, $session, $cart_prods, $error) = @_;

  my @required = BSE::Custom->required_fields($CGI::Q, $session->{custom});
  push(@required, qw(cardHolder cardExpiry)) if $wantcard;
  for my $field (@required) {
    defined($q->param($field)) && length($q->param($field))
      or do { $$error = "Field $field is required"; return 0 };
  }
  defined($q->param('email')) && $q->param('email') =~ /.\@./
    or do { $$error = "Please enter a valid email address"; return 0 };

  if ($wantcard) {
    defined($q->param('cardNumber')) && $q->param('cardNumber') =~ /^\d+$/
      or do { $$error = "Please enter a credit card number"; return 0 };
  }

  require 'Orders.pm';
  require 'Order.pm';
  require 'OrderItems.pm';
  require 'OrderItem.pm';

  my %order;
  my @cart = @{$session->{cart}};
  @cart or 
    do { $$error = 'You have no items in your shopping cart'; return 0 };

  # so we can quickly check for columns
  my @columns = Order->columns;
  my %columns; 
  @columns{@columns} = @columns;

  for my $field ($q->param()) {
    $order->{$field_map{$field} || $field} = $q->param($field)
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
  $order->{total} += BSE::Custom->total_extras(\@cart, \@products, 
					     $session->{custom});
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
    BSE::Custom->order_save($q, $order, \@cart, \@products, $session->{custom});
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
     money =>
     sub {
       my ($func, $args) = split ' ', $_[0], 2;
       $acts->{$func} || return "<: money $_[0] :>";
       return sprintf("%.02f", $acts->{$func}->($args)/100);
     },
    );
}

1;
