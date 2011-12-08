package BSE::UI::Shop;
use strict;
use base 'BSE::UI::Dispatch';
use BSE::Util::HTML qw(:default popup_menu);
use BSE::Util::SQL qw(now_sqldate now_sqldatetime);
use BSE::Shop::Util qw(:payment need_logon shop_cart_tags payment_types nice_options 
                       cart_item_opts basic_tags order_item_opts);
use BSE::CfgInfo qw(custom_class credit_card_class bse_default_country);
use BSE::TB::Orders;
use BSE::TB::OrderItems;
use BSE::Util::Tags qw(tag_error_img tag_hash tag_article);
use Products;
use BSE::TB::Seminars;
use DevHelp::Validate qw(dh_validate dh_validate_hash);
use Digest::MD5 'md5_hex';
use BSE::Shipping;
use BSE::Countries qw(bse_country_code);
use BSE::Util::Secure qw(make_secret);

our $VERSION = "1.024";

use constant MSG_SHOP_CART_FULL => 'Your shopping cart is full, please remove an item and try adding an item again';

my %actions =
  (
   add => 1,
   addmultiple => 1,
   cart => 1,
   checkout => 1,
   checkupdate => 1,
   recheckout => 1,
   confirm => 1,
   recalc=>1,
   recalculate => 1,
   #purchase => 1,
   order => 1,
   show_payment => 1,
   payment => 1,
   orderdone => 1,
   location => 1,
   paypalret => 1,
   paypalcan => 1,
   emptycart => 1,
  );

# map of SiteUser field names to order field names - mostly
my %field_map = 
  (
   name1 => 'billFirstName',
   name2 => 'billLastName',
   address => 'billStreet',
   organization => 'billOrganization',
   city => 'billSuburb',
   postcode => 'billPostCode',
   state => 'billState',
   country => 'billCountry',
   email => 'billEmail',
   telephone => 'billTelephone',
   facsimile => 'billFacsimile',
   delivMobile => 'billMobile', # temporary hack
   unknown1 => 'delivMobile', # more hackery
  );

my %rev_field_map = reverse %field_map;

sub actions { \%actions }

sub default_action { 'cart' }

sub other_action {
  my ($class, $cgi) = @_;

  for my $key ($cgi->param()) {
    if ($key =~ /^delete_(\d+)(?:\.x)?$/) {
      return ( remove_item => $1 );
    }
    elsif ($key =~ /^(?:a_)?addsingle(\d+)(?:\.x)?$/) {
      return ( addsingle => $1 );
    }
  }

  return;
}

sub req_cart {
  my ($class, $req, $msg) = @_;

  my @cart = @{$req->session->{cart} || []};
  my @cart_prods;
  my @items = $class->_build_items($req, \@cart_prods);
  my $item_index = -1;
  my @options;
  my $option_index;
  
  $req->session->{custom} ||= {};
  my %custom_state = %{$req->session->{custom}};

  my $cust_class = custom_class($req->cfg);
  $cust_class->enter_cart(\@cart, \@cart_prods, \%custom_state, $req->cfg); 
  $msg = '' unless defined $msg;
  $msg = escape_html($msg);

  $msg ||= $req->message;
  
  my %acts;
  %acts =
    (
     $cust_class->cart_actions(\%acts, \@cart, \@cart_prods, \%custom_state, 
			       $req->cfg),
     shop_cart_tags(\%acts, \@items, \@cart_prods, $req, 'cart'),
     basic_tags(\%acts),
     msg => $msg,
    );
  $req->session->{custom} = \%custom_state;
  $req->session->{order_info_confirmed} = 0;

  # intended to ajax enable the shop cart with partial templates
  my $template = 'cart';
  my $embed = $req->cgi->param('embed');
  if (defined $embed and $embed =~ /^\w+$/) {
    $template = "include/cart_$embed";
  }
  return $req->response($template, \%acts);
}

=item a_emptycart

Empty the shopping cart.

Refreshes to the URL in C<r> or the cart otherwise.

Flashes msg:bse/shop/cart/empty unless C<r> is supplied.

=cut

sub req_emptycart {
  my ($self, $req) = @_;

  my $old = $req->session->{cart};;
  $req->session->{cart} = [];

  my $refresh = $req->cgi->param('r');
  unless ($refresh) {
    $refresh = $req->user_url(shop => 'cart');
    $req->flash("msg:bse/shop/cart/empty");
  }

  return _add_refresh($refresh, $req, !$old);
}

sub req_add {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;

  my $quantity = $cgi->param('quantity');
  $quantity ||= 1;

  my $error;
  my $refresh_logon;
  my ($product, $options, $extras);
  my $addid = $cgi->param('id');
  if (defined $addid) {
    ($product, $options, $extras)
      = $class->_validate_add_by_id($req, $addid, $quantity, \$error, \$refresh_logon);
  }
  else {
    my $code = $cgi->param('code');
    if (defined $code) {
      ($product, $options, $extras)
	= $class->_validate_add_by_code($req, $code, $quantity, \$error, \$refresh_logon);
    }
    else {
      return $class->req_cart($req, "No product id or code supplied");
    }
  }
  if ($refresh_logon) {
    return $class->_refresh_logon($req, @$refresh_logon);
  }
  elsif ($error) {
    return $class->req_cart($req, $error);
  }

  if ($cgi->param('empty')) {
    $req->session->{cart} = [];
  }

  $req->session->{cart} ||= [];
  my @cart = @{$req->session->{cart}};
  my $started_empty = @cart == 0;

  my $found;
  for my $item (@cart) {
    $item->{productId} eq $product->{id} && _same_options($item->{options}, $options)
      or next;

    ++$found;
    $item->{units} += $quantity;
    last;
  }
  unless ($found) {
    my $cart_limit = $req->cfg->entry('shop', 'cart_entry_limit');
    if (defined $cart_limit && @cart >= $cart_limit) {
      return $class->req_cart($req, $req->text('shop/cartfull', MSG_SHOP_CART_FULL));
    }
    push @cart, 
      { 
       productId => $product->{id}, 
       units => $quantity, 
       price=> scalar $product->price(user => scalar $req->siteuser),
       options=>$options,
       %$extras,
      };
  }

  $req->session->{cart} = \@cart;
  $req->session->{order_info_confirmed} = 0;

  my $refresh = $cgi->param('r');
  unless ($refresh) {
    $refresh = $req->user_url(shop => 'cart');
  }

  # speed for ajax
  if ($refresh eq 'ajaxcart') {
    return $class->req_cart($req);
  }

  return _add_refresh($refresh, $req, $started_empty);
}

sub req_addsingle {
  my ($class, $req, $addid) = @_;

  my $cgi = $req->cgi;

  $addid ||= '';
  my $quantity = $cgi->param("qty$addid");
  defined $quantity && $quantity =~ /\S/
    or $quantity = 1;

  my $error;
  my $refresh_logon;
  my ($product, $options, $extras)
    = $class->_validate_add_by_id($req, $addid, $quantity, \$error, \$refresh_logon);
  if ($refresh_logon) {
    return $class->_refresh_logon($req, @$refresh_logon);
  }
  elsif ($error) {
    return $class->req_cart($req, $error);
  }    

  if ($cgi->param('empty')) {
    $req->session->{cart} = [];
  }

  $req->session->{cart} ||= [];
  my @cart = @{$req->session->{cart}};
  my $started_empty = @cart == 0;
 
  my $found;
  for my $item (@cart) {
    $item->{productId} eq $addid && _same_options($item->{options}, $options)
      or next;

    ++$found;
    $item->{units} += $quantity;
    last;
  }
  unless ($found) {
    my $cart_limit = $req->cfg->entry('shop', 'cart_entry_limit');
    if (defined $cart_limit && @cart >= $cart_limit) {
      return $class->req_cart($req, $req->text('shop/cartfull', MSG_SHOP_CART_FULL));
    }
    push @cart, 
      { 
       productId => $addid, 
       units => $quantity, 
       price=> scalar $product->price(user => scalar $req->siteuser),
       options=>$options,
       %$extras,
      };
  }

  $req->session->{cart} = \@cart;
  $req->session->{order_info_confirmed} = 0;

  my $refresh = $cgi->param('r');
  unless ($refresh) {
    $refresh = $req->user_url(shop => 'cart');
  }

  # speed for ajax
  if ($refresh eq 'ajaxcart') {
    return $class->req_cart($req);
  }

  return _add_refresh($refresh, $req, $started_empty);
}

sub req_addmultiple {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my @qty_keys = map /^qty(\d+)/, $cgi->param;

  my @messages;
  my %additions;
  for my $addid (@qty_keys) {
    my $quantity = $cgi->param("qty$addid");
    defined $quantity && $quantity =~ /^\s*\d+\s*$/
      or next;

    my $error;
    my $refresh_logon;
    my ($product, $options, $extras) =
      $class->_validate_add_by_id($req, $addid, $quantity, \$error, \$refresh_logon);
    if ($refresh_logon) {
      return $class->_refresh_logon($req, @$refresh_logon);
    }
    elsif ($error) {
      return $class->req_cart($req, $error);
    }
    if ($product->{options}) {
      push @messages, "$product->{title} has options, you need to use the product page to add this product";
      next;
    }
    $additions{$addid} = 
      { 
       id => $product->{id},
       product => $product, 
       extras => $extras,
       quantity => $quantity,
      };
  }

  my @qtys = $cgi->param("qty");
  my @ids = $cgi->param("id");
  for my $addid (@ids) {
    my $quantity = shift @qtys;
    $addid =~ /^\d+$/
      or next;
    $additions{$addid}
      and next;
    defined $quantity or $quantity = 1;
    $quantity =~ /^\d+$/
      or next;
    $quantity
      or next;
    my ($error, $refresh_logon);

    my ($product, $options, $extras) =
      $class->_validate_add_by_id($req, $addid, $quantity, \$error, \$refresh_logon);
    if ($refresh_logon) {
      return $class->_refresh_logon($req, @$refresh_logon);
    }
    elsif ($error) {
      return $class->req_cart($req, $error);
    }
    if ($product->{options}) {
      push @messages, "$product->{title} has options, you need to use the product page to add this product";
      next;
    }
    $additions{$addid} = 
      { 
       id => $product->{id},
       product => $product, 
       extras => $extras,
       quantity => $quantity,
      };
  }
  
  my $started_empty = 0;
  if (keys %additions) {
    if ($cgi->param('empty')) {
      $req->session->{cart} = [];
    }
    $req->session->{cart} ||= [];
    my @cart = @{$req->session->{cart}};
    $started_empty = @cart == 0;
    for my $item (@cart) {
      @{$item->{options}} == 0 or next;

      my $addition = delete $additions{$item->{productId}}
	or next;

      $item->{units} += $addition->{quantity};
    }

    my $cart_limit = $req->cfg->entry('shop', 'cart_entry_limit');

    my @additions = grep $_->{quantity} > 0, values %additions;

    my $error;
    for my $addition (@additions) {
      my $product = $addition->{product};

      if (defined $cart_limit && @cart >= $cart_limit) {
	$error = $req->text('shop/cartfull', MSG_SHOP_CART_FULL);
	last;
      }

      push @cart, 
	{ 
	 productId => $product->{id},
	 units => $addition->{quantity}, 
	 price=> scalar $product->price(user => scalar $req->siteuser),
	 options=>[],
	 %{$addition->{extras}},
	};
    }
    
    $req->session->{cart} = \@cart;
    $req->session->{order_info_confirmed} = 0;
    $error
      and return $class->req_cart($req, $error);
  }

  my $refresh = $cgi->param('r');
  unless ($refresh) {
    $refresh = $req->user_url(shop => 'cart');
  }
  if (@messages) {
    my $sep = $refresh =~ /\?/ ? '&' : '?';
    
    for my $message (@messages) {
      $refresh .= $sep . "m=" . escape_uri($message);
      $sep = '&';
    }
  }

  # speed for ajax
  if ($refresh eq 'ajaxcart') {
    return $class->req_cart($req);
  }

  return _add_refresh($refresh, $req, $started_empty);
}

sub tag_ifUser {
  my ($user, $args) = @_;

  if ($args) {
    if ($user) {
      return defined $user->{$args} && $user->{$args};
    }
    else {
      return 0;
    }
  }
  else {
    return defined $user;
  }
}

sub req_checkout {
  my ($class, $req, $message, $olddata) = @_;

  my $errors = {};
  if (defined $message) {
    if (ref $message) {
      $errors = $message;
      $message = $req->message($errors);
    }
  }
  else {
    $message = '';
  }
  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  my $need_delivery = ( $olddata ? $cgi->param("need_delivery") : $req->session->{order_need_delivery} ) || 0;

  $class->update_quantities($req);
  my @cart = @{$req->session->{cart}};

  @cart or return $class->req_cart($req);

  my @cart_prods;
  my @items = $class->_build_items($req, \@cart_prods);

  if (my ($msg, $id) = $class->_need_logon($req, \@cart, \@cart_prods)) {
    return $class->_refresh_logon($req, $msg, $id);
    return;
  }

  my $user = $req->siteuser;

  $req->session->{custom} ||= {};
  my %custom_state = %{$req->session->{custom}};

  my $cust_class = custom_class($cfg);
  $cust_class->enter_cart(\@cart, \@cart_prods, \%custom_state, $cfg);

  my $affiliate_code = $req->session->{affiliate_code};
  defined $affiliate_code or $affiliate_code = '';

  my $order_info = $req->session->{order_info};

  my $old = sub {
    my $field = $_[0];
    my $value;

    if ($olddata) {
      $value = $cgi->param($field);
    }
    elsif ($order_info && defined $order_info->{$field}) {
      $value = $order_info->{$field};
    }
    else {
      $rev_field_map{$field} and $field = $rev_field_map{$field};
      $value = $user && defined $user->{$field} ? $user->{$field} : '';
    }

    defined $value or $value = '';
    return $value;
  };

  # shipping handling, if enabled
  my $shipping_select = ''; # select of shipping types
  my ($delivery_in, $shipping_cost, $shipping_method);
  my $shipping_error = '';
  my $shipping_name = '';
  my $prompt_ship = $cfg->entry("shop", "shipping", 0);
  if ($prompt_ship) {
    # Get a list of couriers
    my $sel_cn = $old->("shipping_name") || "";
    my %fake_order;
    my %fields = $class->_order_fields($req);
    $class->_order_hash($req, \%fake_order, \%fields);
    my $country = $fake_order{delivCountry} || bse_default_country($cfg);
    my $country_code = bse_country_code($country);
    my $suburb = $fake_order{delivSuburb};
    my $postcode = $fake_order{delivPostCode};

    $country_code
      or $errors->{delivCountry} = "Unknown country name $country";

    my @couriers = BSE::Shipping->get_couriers($cfg);

    if ($country_code and $postcode) {
      @couriers = grep $_->can_deliver(country => $country_code,
				       suburb => $suburb,
				       postcode => $postcode), @couriers;
    }
    
    my ($sel_cour) = grep $_->name eq $sel_cn, @couriers;
    # if we don't match against the list (perhaps because of a country
    # change) the first item in the list will be selected by the
    # browser anyway, so select it ourselves and display an
    # appropriate shipping cost for the item
    unless ($sel_cour) {
      $sel_cour = $couriers[0];
      $sel_cn = $sel_cour->name;
    }
    if ($sel_cour and $postcode and $suburb and $country_code) {
      my @parcels = BSE::Shipping->package_order($cfg, \%fake_order, \@items);
      $shipping_cost = $sel_cour->calculate_shipping
	(
	 parcels => \@parcels,
	 suburb => $suburb,
	 postcode => $postcode,
	 country => $country_code,
	 products => \@cart_prods,
	 items => \@items,
	);
      $delivery_in = $sel_cour->delivery_in();
      $shipping_method = $sel_cour->description();
      $shipping_name = $sel_cour->name;
      unless (defined $shipping_cost) {
	$shipping_error = "$shipping_method: " . $sel_cour->error_message;
	$errors->{shipping_name} = $shipping_error;

	# use the last one, which should be the Null shipper
	$sel_cour = $couriers[-1];
	$sel_cn = $sel_cour->name;
	$shipping_method = $sel_cour->description;
      }
    }
    
    $shipping_select = popup_menu
      (
       -name => "shipping_name",
       -id => "shipping_name",
       -values => [ map $_->name, @couriers ],
       -labels => { map { $_->name => $_->description } @couriers },
       -default => $sel_cn,
      );
  }

  if (!$message && keys %$errors) {
    $message = $req->message($errors);
  }

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     shop_cart_tags(\%acts, \@items, \@cart_prods, $req, 'checkout'),
     basic_tags(\%acts),
     message => $message,
     msg => $message,
     old => sub { escape_html($old->($_[0])); },
     $cust_class->checkout_actions(\%acts, \@cart, \@cart_prods, 
				   \%custom_state, $req->cgi, $cfg),
     ifUser => [ \&tag_ifUser, $user ],
     user => $user ? [ \&tag_hash, $user ] : '',
     affiliate_code => escape_html($affiliate_code),
     error_img => [ \&tag_error_img, $cfg, $errors ],
     ifShipping => $prompt_ship,
     shipping_select => $shipping_select,
     delivery_in => escape_html($delivery_in),
     shipping_cost => $shipping_cost,
     shipping_method => escape_html($shipping_method),
     shipping_error => escape_html($shipping_error),
     shipping_name => $shipping_name,
     ifNeedDelivery => $need_delivery,
    );
  $req->session->{custom} = \%custom_state;
  my $tmp = $acts{total};
  $acts{total} =
    sub {
        my $total = &$tmp();
        $total += $shipping_cost if $total and $shipping_cost;
        return $total;
    };

  return $req->response('checkoutnew', \%acts);
}

sub req_checkupdate {
  my ($class, $req) = @_;

  $req->session->{cart} ||= [];
  my @cart = @{$req->session->{cart}};
  my @cart_prods = map { Products->getByPkey($_->{productId}) } @cart;
  $req->session->{custom} ||= {};
  my %custom_state = %{$req->session->{custom}};
  custom_class($req->cfg)
      ->checkout_update($req->cgi, \@cart, \@cart_prods, \%custom_state, $req->cfg);
  $req->session->{custom} = \%custom_state;
  $req->session->{order_info_confirmed} = 0;
  
  return $class->req_checkout($req, "", 1);
}

sub req_remove_item {
  my ($class, $req, $index) = @_;

  $req->session->{cart} ||= [];
  my @cart = @{$req->session->{cart}};
  if ($index >= 0 && $index < @cart) {
    splice(@cart, $index, 1);
  }
  $req->session->{cart} = \@cart;
  $req->session->{order_info_confirmed} = 0;

  return BSE::Template->get_refresh($req->user_url(shop => 'cart'), $req->cfg);
}

sub _order_fields {
  my ($self, $req) = @_;

  my %fields = BSE::TB::Order->valid_fields($req->cfg);
  my $cust_class = custom_class($req->cfg);
  my @required = 
    $cust_class->required_fields($req->cgi, $req->session->{custom}, $req->cfg);

  for my $name (@required) {
    $fields{$name}{required} = 1;
  }

  return %fields;
}

sub _order_hash {
  my ($self, $req, $values, $fields) = @_;

  my $cgi = $req->cgi;
  for my $name (keys %$fields) {
    my ($value) = $cgi->param($name);
    defined $value or $value = "";
    $values->{$name} = $value;
  }

  unless ($cgi->param("need_delivery")) {
    my $map = BSE::TB::Order->billing_to_delivery_map;
    keys %$map; # reset iterator
    while (my ($billing, $delivery) = each %$map) {
      $values->{$delivery} = $values->{$billing};
    }
  }
}

# saves order and refresh to payment page
sub req_order {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  $req->session->{cart} && @{$req->session->{cart}}
    or return $class->req_cart($req, "Your cart is empty");

  my $msg;
  $class->_validate_cfg($req, \$msg)
    or return $class->req_cart($req, $msg);

  my @products;
  my @items = $class->_build_items($req, \@products);

  my $id;
  if (($msg, $id) = $class->_need_logon($req, \@items, \@products)) {
    return $class->_refresh_logon($req, $msg, $id);
  }

  my %fields = $class->_order_fields($req);
  my %rules = BSE::TB::Order->valid_rules($cfg);
  
  my %errors;
  my %values;
  $class->_order_hash($req, \%values, \%fields);

  dh_validate_hash(\%values, \%errors, { rules=>\%rules, fields=>\%fields },
		   $cfg, 'Shop Order Validation');
  my $prompt_ship = $cfg->entry("shop", "shipping", 0);
  if ($prompt_ship) {
    my $country = $values{delivCountry} || bse_default_country($cfg);
    my $country_code = bse_country_code($country);
    $country_code
      or $errors{delivCountry} = "Unknown country name $country";
  }
  keys %errors
    and return $class->req_checkout($req, \%errors, 1);

  $class->_fillout_order($req, \%values, \@items, \@products, \$msg, 'payment')
    or return $class->req_checkout($req, $msg, 1);

  $req->session->{order_info} = \%values;
  $req->session->{order_need_delivery} = $cgi->param("need_delivery");
  $req->session->{order_info_confirmed} = 1;

  # skip payment page if nothing to pay
  if ($values{total} == 0) {
    return $class->req_payment($req);
  }
  else {
    return BSE::Template->get_refresh($req->user_url(shop => 'show_payment'), $req->cfg);
  }
}

=item a_show_payment

Allows the customer to pay for an existing order.

Parameters:

=over

=item *

orderid - the order id to be paid (Optional, otherwise displays the
cart for payment).

=back

Template: checkoutpay

=cut


sub req_show_payment {
  my ($class, $req, $errors) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  my @items;
  my @products;
  my $order;

  # ideally supply order_id to be consistent with a_payment.
  my $order_id = $cgi->param('orderid') || $cgi->param("order_id");
  if ($order_id) {
    $order_id =~ /^\d+$/
      or return $class->req_cart($req, "No or invalid order id supplied");
    
    my $user = $req->siteuser
      or return $class->_refresh_logon
	($req, "Please logon before paying your existing order", "logonpayorder",
	 undef, { a_show_payment => 1, orderid => $order_id });
    
    require BSE::TB::Orders;
    $order = BSE::TB::Orders->getByPkey($order_id)
      or return $class->req_cart($req, "Unknown order id");
    
    $order->siteuser_id == $user->id
      or return $class->req_cart($req, "You can only pay for your own orders");
    
    $order->paidFor
      and return $class->req_cart($req, "Order $order->{id} has been paid");
    
    @items = $order->items;
    @products = $order->products;
  }
  else {
    $req->session->{order_info_confirmed}
      or return $class->req_checkout($req, 'Please proceed via the checkout page');
    
    $req->session->{cart} && @{$req->session->{cart}}
      or return $class->req_cart($req, "Your cart is empty");
    
    $order = $req->session->{order_info}
      or return $class->req_checkout($req, "You need to enter order information first");

    @items = $class->_build_items($req, \@products);
  }

  $errors ||= {};
  my $msg = $req->message($errors);

  my @pay_types = payment_types($cfg);
  my @payment_types = map $_->{id}, grep $_->{enabled}, @pay_types;
  my %types_by_name = map { $_->{name} => $_->{id} } @pay_types;
  @payment_types or @payment_types = ( PAYMENT_CALLME );
  @payment_types = sort { $a <=> $b } @payment_types;
  my %payment_types = map { $_=> 1 } @payment_types;
  my $payment;
  $errors and $payment = $cgi->param('paymentType');
  defined $payment or $payment = $payment_types[0];

  my %acts;
  %acts =
    (
     basic_tags(\%acts),
     message => $msg,
     msg => $msg,
     order => [ \&tag_hash, $order ],
     shop_cart_tags(\%acts, \@items, \@products, $req, 'payment'),
     ifMultPaymentTypes => @payment_types > 1,
     checkedPayment => [ \&tag_checkedPayment, $payment, \%types_by_name ],
     ifPayments => [ \&tag_ifPayments, \@payment_types, \%types_by_name ],
     paymentTypeId => [ \&tag_paymentTypeId, \%types_by_name ],
     error_img => [ \&tag_error_img, $cfg, $errors ],
     total => $order->{total},
     delivery_in => $order->{delivery_in},
     shipping_cost => $order->{shipping_cost},
     shipping_method => $order->{shipping_method},
    );
  for my $type (@pay_types) {
    my $id = $type->{id};
    my $name = $type->{name};
    $acts{"if${name}Payments"} = exists $payment_types{$id};
    $acts{"if${name}FirstPayment"} = $payment_types[0] == $id;
    $acts{"checkedIfFirst$name"} = $payment_types[0] == $id ? "checked " : "";
    $acts{"checkedPayment$name"} = $payment == $id ? 'checked="checked" ' : "";
  }

  return $req->response('checkoutpay', \%acts);
}

my %nostore =
  (
   cardNumber => 1,
   cardExpiry => 1,
   delivery_in => 1,
   cardVerify => 1,
   ccName => 1,
  );

my %bill_ccmap =
  (
   # hash of CC payment parameter names to arrays of billing address fields
   firstname => "billFirstName",
   lastname => "billLastName",
   address1 => "billStreet",
   address2 => "billStreet2",
   postcode => "billPostCode",
   state => "billState",
   suburb => "billSuburb",
   email => "billEmail",
  );

sub req_payment {
  my ($class, $req, $errors) = @_;

  require BSE::TB::Orders;
  my $cgi = $req->cgi;
  my $order_id = $cgi->param("order_id");
  my $user = $req->siteuser;
  my $order;
  my $order_values;
  my $old_order; # true if we're paying an old order
  if ($order_id) {
    unless ($user) {
      return $class->_refresh_logon
	(
	 $req,
	 "Please logon before paying your existing order",
	 "logonpayorder",
	 undef,
	 { a_show_payment => 1, orderid => $order_id }
	);
    }
    $order_id =~ /^\d+$/
      or return $class->req_cart($req, "Invalid order id");
    $order = BSE::TB::Orders->getByPkey($order_id)
      or return $class->req_cart($req, "Unknown order id");
    $order->siteuser_id == $user->id
      or return $class->req_cart($req, "You can only pay for your own orders");

    $order->paidFor
      and return $class->req_cart($req, "Order $order->{id} has been paid");

    $order_values = $order;
    $old_order = 1;
  }
  else {
    $req->session->{order_info_confirmed}
      or return $class->req_checkout($req, 'Please proceed via the checkout page');

    $order_values = $req->session->{order_info}
      or return $class->req_checkout($req, "You need to enter order information first");
    $old_order = 0;
  }

  my $cfg = $req->cfg;
  my $session = $req->session;

  my $paymentType;
  if ($order_values->{total} != 0) {
    my @pay_types = payment_types($cfg);
    my @payment_types = map $_->{id}, grep $_->{enabled}, @pay_types;
    my %pay_types = map { $_->{id} => $_ } @pay_types;
    my %types_by_name = map { $_->{name} => $_->{id} } @pay_types;
    @payment_types or @payment_types = ( PAYMENT_CALLME );
    @payment_types = sort { $a <=> $b } @payment_types;
    my %payment_types = map { $_=> 1 } @payment_types;
    
    $paymentType = $cgi->param('paymentType');
    defined $paymentType or $paymentType = $payment_types[0];
    $payment_types{$paymentType}
      or return $class->req_show_payment($req, { paymentType => "Invalid payment type" } , 1);
    
    my @required;
    push @required, @{$pay_types{$paymentType}{require}};
    
    my %fields = BSE::TB::Order->valid_payment_fields($cfg);
    my %rules = BSE::TB::Order->valid_payment_rules($cfg);
    for my $field (@required) {
      if (exists $fields{$field}) {
	$fields{$field}{required} = 1;
      }
      else {
	$fields{$field} = { description => $field, required=> 1 };
      }
    }
    
    my %errors;
    dh_validate($cgi, \%errors, { rules => \%rules, fields=>\%fields },
		$cfg, 'Shop Order Validation');
    keys %errors
      and return $class->req_show_payment($req, \%errors);

    for my $field (keys %fields) {
      unless ($nostore{$field}) {
	($order_values->{$field}) = $cgi->param($field);
      }
    }

  }
  else {
    $paymentType = -1;
  }

  $order_values->{paymentType} = $paymentType;
  my @dbitems;
  my @products;
  my %subscribing_to;
  if ($order) {
    @dbitems = $order->items;
    @products = $order->products;
    for my $product (@products) {
      my $sub = $product->subscription;
      if ($sub) {
	$subscribing_to{$sub->{text_id}} = $sub;
      }
    }
  }
  else {
    $order_values->{filled} = 0;
    $order_values->{paidFor} = 0;
    
    my @items = $class->_build_items($req, \@products);
    
    if ($session->{order_work}) {
      $order = BSE::TB::Orders->getByPkey($session->{order_work});
    }
    if ($order && !$order->{complete}) {
      my @columns = BSE::TB::Order->columns;
      shift @columns; # don't set id
      my %columns; 
      @columns{@columns} = @columns;
      
      for my $col (@columns) {
	defined $order_values->{$col} or $order_values->{$col} = '';
      }
      
      my @data = @{$order_values}{@columns};
      shift @data;
    
      print STDERR "Recycling order $order->{id}\n";
      
      my @allbutid = @columns;
      shift @allbutid;
      @{$order}{@allbutid} = @data;
      
      $order->clear_items;
      delete $session->{order_work};
      eval {
	tied(%$session)->save;
      };
    }
    else {
      $order = BSE::TB::Orders->make(%$order_values)
	or die "Cannot add order";
    }
    
    my @item_cols = BSE::TB::OrderItem->columns;
    for my $row_num (0..$#items) {
      my $item = $items[$row_num];
      my $product = $products[$row_num];
      my %item = %$item;
      $item{orderId} = $order->{id};
      $item{max_lapsed} = 0;
      if ($product->{subscription_id} != -1) {
	my $sub = $product->subscription;
	$item{max_lapsed} = $sub->{max_lapsed} if $sub;
      }
      defined $item{session_id} or $item{session_id} = 0;
      $item{options} = ""; # not used for new orders
      my @data = @item{@item_cols};
    shift @data;
      my $dbitem = BSE::TB::OrderItems->add(@data);
      push @dbitems, $dbitem;
      
      if ($item->{options} and @{$item->{options}}) {
	require BSE::TB::OrderItemOptions;
	my @option_descs = $product->option_descs($cfg, $item->{options});
	my $display_order = 1;
	for my $option (@option_descs) {
	  BSE::TB::OrderItemOptions->make
	      (
	       order_item_id => $dbitem->{id},
	       original_id => $option->{id},
	       name => $option->{desc},
	       value => $option->{value},
	       display => $option->{display},
	       display_order => $display_order++,
	      );
	}
      }
      
      my $sub = $product->subscription;
      if ($sub) {
	$subscribing_to{$sub->{text_id}} = $sub;
      }

      if ($item->{session_id}) {
	require BSE::TB::SeminarSessions;
	my $session = BSE::TB::SeminarSessions->getByPkey($item->{session_id});
	my $options = join(",", @{$item->{options}});
	$session->add_attendee($user, 
			       customer_instructions => $order->{instructions},
			       options => $options);
      }
    }
  }

  $order->set_randomId(make_secret($cfg));
  $order->{ccOnline} = 0;
  
  my $ccprocessor = $cfg->entry('shop', 'cardprocessor');
  if ($paymentType == PAYMENT_CC) {
    my $ccNumber = $cgi->param('cardNumber');
    my $ccExpiry = $cgi->param('cardExpiry');
    my $ccName   = $cgi->param('ccName');
    
    if ($ccprocessor) {
      my $cc_class = credit_card_class($cfg);
      
      $order->{ccOnline} = 1;
      
      $ccExpiry =~ m!^(\d+)\D(\d+)$! or die;
      my ($month, $year) = ($1, $2);
      $year > 2000 or $year += 2000;
      my $expiry = sprintf("%04d%02d", $year, $month);
      my $verify = $cgi->param('cardVerify');
      defined $verify or $verify = '';
      my %more;
      while (my ($cc_field, $order_field) = each %bill_ccmap) {
	if ($order->$order_field()) {
	  $more{$cc_field} = $order->$order_field();
	}
      }
      my $result = $cc_class->payment
	(
	 orderno => $order->{id},
	 amount => $order->{total},
	 cardnumber => $ccNumber,
	 nameoncard => $ccName,
	 expirydate => $expiry,
	 cvv => $verify,
	 ipaddress => $ENV{REMOTE_ADDR},
	 %more,
	);
      unless ($result->{success}) {
	use Data::Dumper;
	print STDERR Dumper($result);
	# failed, back to payments
	$order->{ccSuccess}     = 0;
	$order->{ccStatus}      = $result->{statuscode};
	$order->{ccStatus2}     = 0;
	$order->{ccStatusText}  = $result->{error};
	$order->{ccTranId}      = '';
	$order->save;
	my %errors;
	$errors{cardNumber} = $result->{error};
	$session->{order_work} = $order->{id};
	return $class->req_show_payment($req, \%errors);
      }
      
      $order->{ccSuccess}	    = 1;
      $order->{ccReceipt}	    = $result->{receipt};
      $order->{ccStatus}	    = 0;
      $order->{ccStatus2}	    = 0;
      $order->{ccStatusText}  = '';
      $order->{ccTranId}	    = $result->{transactionid};
      $order->set_ccPANTruncate($ccNumber);
      defined $order->{ccTranId} or $order->{ccTranId} = '';
      $order->{paidFor}	    = 1;
    }
    else {
      $ccNumber =~ tr/0-9//cd;
      $order->{ccExpiryHash} = md5_hex($ccExpiry);
      $order->set_ccPANTruncate($ccNumber);
    }
    $order->set_ccName($ccName);
  }
  elsif ($paymentType == PAYMENT_PAYPAL) {
    require BSE::PayPal;
    my $msg;
    my $url = BSE::PayPal->payment_url(order => $order,
				       user => $user,
				       msg => \$msg);
    unless ($url) {
      $session->{order_work} = $order->{id};
      my %errors;
      $errors{_} = "PayPal error: $msg" if $msg;
      return $class->req_show_payment($req, \%errors);
    }

    # have to mark it complete so it doesn't get used by something else
    return BSE::Template->get_refresh($url, $req->cfg);
  }

  # order complete
  $order->set_complete(1);
  $order->set_stage("unprocessed");
  $order->save;

  $class->_finish_order($req, $order);

  return BSE::Template->get_refresh($req->user_url(shop => 'orderdone'), $req->cfg);
}

# do final processing of an order after payment
sub _finish_order {
  my ($self, $req, $order) = @_;


  my $custom = custom_class($req->cfg);
  $custom->can("order_complete")
    and $custom->order_complete($req->cfg, $order);

  # set the order displayed by orderdone
  $req->session->{order_completed} = $order->{id};
  $req->session->{order_completed_at} = time;

  $self->_send_order($req, $order);

  # empty the cart ready for the next order
  delete @{$req->session}{qw/order_info order_info_confirmed order_need_delivery cart order_work/};
}

sub req_orderdone {
  my ($class, $req) = @_;

  my $session = $req->session;
  my $cfg = $req->cfg;

  my $id = $session->{order_completed};
  my $when = $session->{order_completed_at};
  $id && defined $when && time < $when + 500
    or return $class->req_cart($req);
    
  my $order = BSE::TB::Orders->getByPkey($id)
    or return $class->req_cart($req);
  my @items = $order->items;
  my @products = map { Products->getByPkey($_->{productId}) } @items;

  my @item_cols = BSE::TB::OrderItem->columns;
  my %copy_cols = map { $_ => 1 } Product->columns;
  delete @copy_cols{@item_cols};
  my @copy_cols = keys %copy_cols;
  my @showitems;
  for my $item_index (0..$#items) {
    my $item = $items[$item_index];
    my $product = $products[$item_index];
    my %entry;
    @entry{@item_cols} = @{$item}{@item_cols};
    @entry{@copy_cols} = @{$product}{@copy_cols};

    push @showitems, \%entry;
  }

  my $cust_class = custom_class($req->cfg);

  my @pay_types = payment_types($cfg);
  my @payment_types = map $_->{id}, grep $_->{enabled}, @pay_types;
  my %pay_types = map { $_->{id} => $_ } @pay_types;
  my %types_by_name = map { $_->{name} => $_->{id} } @pay_types;

  my $item_index = -1;
  my @options;
  my $option_index;
  my $item;
  my $product;
  my $sem_session;
  my $location;
  require BSE::Util::Iterate;
  my $it = BSE::Util::Iterate::Objects->new(cfg => $req->cfg);
  my $message = $req->message();
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     $cust_class->purchase_actions(\%acts, \@items, \@products, 
				   $session->{custom}, $cfg),
     BSE::Util::Tags->static(\%acts, $cfg),
     iterate_items_reset => sub { $item_index = -1; },
     iterate_items => 
     sub { 
       if (++$item_index < @items) {
	 $option_index = -1;
	 @options = order_item_opts($req, $items[$item_index]);
	 undef $sem_session;
	 undef $location;
	 $item = $items[$item_index];
	 $product = $products[$item_index];
	 return 1;
       }
       undef $item;
       undef $sem_session;
       undef $product;
       undef $location;
       return 0;
     },
     item=> sub { escape_html($showitems[$item_index]{$_[0]}); },
     product =>
     sub { 
       return tag_article($product, $cfg, $_[0]);
     },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $items[$item_index]{units} * $items[$item_index]{$what};
     },
     order => sub { escape_html($order->{$_[0]}) },
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
     option => sub { escape_html($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
     ifPayment => [ \&tag_ifPayment, $order->{paymentType}, \%types_by_name ],
     #ifSubscribingTo => [ \&tag_ifSubscribingTo, \%subscribing_to ],
     session => [ \&tag_session, \$item, \$sem_session ],
     location => [ \&tag_location, \$item, \$location ],
     msg => $message,
     delivery_in => $order->{delivery_in},
     shipping_cost => $order->{shipping_cost},
     shipping_method => $order->{shipping_method},
     $it->make
     (
      single => "orderpaidfile",
      plural => "orderpaidfiles",
      code => [ paid_files => $order ],
     ),
    );
  for my $type (@pay_types) {
    my $id = $type->{id};
    my $name = $type->{name};
    $acts{"if${name}Payment"} = $order->{paymentType} == $id;
  }

  return $req->response('checkoutfinal', \%acts);
}

sub tag_session {
  my ($ritem, $rsession, $arg) = @_;

  $$ritem or return '';

  $$ritem->{session_id} or return '';

  unless ($$rsession) {
    require BSE::TB::SeminarSessions;
    $$rsession = BSE::TB::SeminarSessions->getByPkey($$ritem->{session_id})
      or return '';
  }

  my $value = $$rsession->{$arg};
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

sub tag_ifPayment {
  my ($payment, $types_by_name, $args) = @_;

  my $type = $args;
  if ($type !~ /^\d+$/) {
    return '' unless exists $types_by_name->{$type};
    $type = $types_by_name->{$type};
  }

  return $payment == $type;
}

sub tag_paymentTypeId {
  my ($types_by_name, $args) = @_;

  if (exists $types_by_name->{$args}) {
    return $types_by_name->{$args};
  }

  return '';
}


sub _validate_cfg {
  my ($class, $req, $rmsg) = @_;

  my $cfg = $req->cfg;
  my $from = $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
  unless ($from && $from =~ /.\@./) {
    $$rmsg = "Configuration error: shop from address not set";
    return;
  }
  my $toEmail = $cfg->entry('shop', 'to_email', $Constants::SHOP_TO_EMAIL);
  unless ($toEmail && $toEmail =~ /.\@./) {
    $$rmsg = "Configuration error: shop to_email address not set";
    return;
  }

  return 1;
}

sub req_recalc {
  my ($class, $req) = @_;

  $class->update_quantities($req);
  $req->session->{order_info_confirmed} = 0;
  return $class->req_cart($req);
}

sub req_recalculate {
  my ($class, $req) = @_;

  return $class->req_recalc($req);
}

sub _send_order {
  my ($class, $req, $order) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  my $noencrypt = $cfg->entryBool('shop', 'noencrypt', 0);
  my $crypto_class = $cfg->entry('shop', 'crypt_module',
				 $Constants::SHOP_CRYPTO);
  my $signing_id = $cfg->entry('shop', 'crypt_signing_id',
			       $Constants::SHOP_SIGNING_ID);
  my $pgp = $cfg->entry('shop', 'crypt_pgp', $Constants::SHOP_PGP);
  my $pgpe = $cfg->entry('shop', 'crypt_pgpe', $Constants::SHOP_PGPE);
  my $gpg = $cfg->entry('shop', 'crypt_gpg', $Constants::SHOP_GPG);
  my $passphrase = $cfg->entry('shop', 'crypt_passphrase', 
			       $Constants::SHOP_PASSPHRASE);
  my $from = $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
  my $toName = $cfg->entry('shop', 'to_name', $Constants::SHOP_TO_NAME);
  my $toEmail = $cfg->entry('shop', 'to_email', $Constants::SHOP_TO_EMAIL);
  my $subject = $cfg->entry('shop', 'subject', $Constants::SHOP_MAIL_SUBJECT);

  my $session = $req->session;
  my %extras = $cfg->entriesCS('extra tags');
  for my $key (keys %extras) {
    # follow any links
    my $data = $cfg->entryVar('extra tags', $key);
    $extras{$key} = sub { $data };
  }

  my @items = $order->items;
  my @products = map $_->product, @items;
  my %subscribing_to;
  for my $product (@products) {
    my $sub = $product->subscription;
    if ($sub) {
      $subscribing_to{$sub->{text_id}} = $sub;
    }
  }

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     %extras,
     custom_class($cfg)
     ->order_mail_actions(\%acts, $order, \@items, \@products, 
			  $session->{custom}, $cfg),
     BSE::Util::Tags->mail_tags(),
     $order->mail_tags(),
     ifSubscribingTo => [ \&tag_ifSubscribingTo, \%subscribing_to ],
    );

  my $email_order = $cfg->entryBool('shop', 'email_order', $Constants::SHOP_EMAIL_ORDER);
  require BSE::ComposeMail;
  if ($email_order) {
    unless ($noencrypt) {
      $acts{cardNumber} = $cgi->param('cardNumber');
      $acts{cardExpiry} = $cgi->param('cardExpiry');
      $acts{cardVerify} = $cgi->param('cardVerify');
    }

    my $mailer = BSE::ComposeMail->new(cfg => $cfg);
    $mailer->start
      (
       to=>$toEmail,
       from=>$from,
       subject=>'New Order '.$order->{id},
       acts => \%acts,
       template => "mailorder",
       log_component => "shop:sendorder:mailowner",
       log_object => $order,
       log_msg => "Order $order->{id} sent to site owner",
      );

    unless ($noencrypt) {
      my %crypt_opts;
      my $sign = $cfg->entryBool('basic', 'sign', 1);
      $sign or $crypt_opts{signing_id} = "";
      $crypt_opts{recipient} =
	$cfg->entry("shop", "crypt_recipient", "$toName $toEmail");
      $mailer->encrypt_body(%crypt_opts);
    }

    unless ($mailer->done) {
      $req->flash_error("Could not mail order to admin: " . $mailer->errstr);
    }

    delete @acts{qw/cardNumber cardExpiry cardVerify/};
  }
  my $to_email = $order->billEmail;
  my $user = $req->siteuser;
  my $to = $to_email;
  if ($user && $user->email eq $to_email) {
    $to = $user;
  }
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);
  my %opts =
    (
     to => $to,
     from => $from,
     subject => $subject . " " . localtime,
     template => "mailconfirm",
     acts => \%acts,
     log_component => "shop:sendorder:mailbuyer",
     log_object => $order,
     log_msg => "Order $order->{id} sent to purchaser $to_email",
    );
  my $bcc_order = $cfg->entry("shop", "bcc_email");
  if ($bcc_order) {
    $opts{bcc} = $bcc_order;
  }
  $mailer->send(%opts)
    or print STDERR "Error sending order to customer: ",$mailer->errstr,"\n";
}

sub _refresh_logon {
  my ($class, $req, $msg, $msgid, $r, $parms) = @_;

  my $securlbase = $req->cfg->entryVar('site', 'secureurl');
  my $url = $securlbase."/cgi-bin/user.pl";
  $parms ||= { checkout => 1 };

  unless ($r) {
    $r = $securlbase."/cgi-bin/shop.pl?" 
      . join("&", map "$_=" . escape_uri($parms->{$_}), keys %$parms);
  }

  my %parms;
  if ($req->cfg->entry('shop registration', 'all')
      || $req->cfg->entry('shop registration', $msgid)) {
    $parms{show_register} = 1;
  }
  $parms{r} = $r;
  if ($msgid) {
    $msg = $req->cfg->entry('messages', $msgid, $msg);
  }
  $parms{message} = $msg if $msg;
  $parms{mid} = $msgid if $msgid;
  $url .= "?" . join("&", map "$_=".escape_uri($parms{$_}), keys %parms);
  
  return BSE::Template->get_refresh($url, $req->cfg);
}

sub _need_logon {
  my ($class, $req, $cart, $cart_prods) = @_;

  return need_logon($req, $cart, $cart_prods);
}

sub tag_checkedPayment {
  my ($payment, $types_by_name, $args) = @_;

  my $type = $args;
  if ($type !~ /^\d+$/) {
    return '' unless exists $types_by_name->{$type};
    $type = $types_by_name->{$type};
  }

  return $payment == $type  ? 'checked="checked"' : '';
}

sub tag_ifPayments {
  my ($enabled, $types_by_name, $args) = @_;

  my $type = $args;
  if ($type !~ /^\d+$/) {
    return '' unless exists $types_by_name->{$type};
    $type = $types_by_name->{$type};
  }

  my @found = grep $_ == $type, @$enabled;

  return scalar @found;
}

sub update_quantities {
  my ($class, $req) = @_;

  my $session = $req->session;
  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my @cart = @{$session->{cart} || []};
  for my $index (0..$#cart) {
    my $new_quantity = $cgi->param("quantity_$index");
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
  $session->{cart} = \@cart;
  $session->{custom} ||= {};
  my %custom_state = %{$session->{custom}};
  custom_class($cfg)->recalc($cgi, \@cart, [], \%custom_state, $cfg);
  $session->{custom} = \%custom_state;
}

sub _build_items {
  my ($class, $req, $products) = @_;

  my $session = $req->session;
  $session->{cart}
    or return;
  my @msgs;
  my @cart = @{$req->session->{cart}}
    or return;
  my @items;
  my @prodcols = Product->columns;
  my @newcart;
  my $today = now_sqldate();
  for my $item (@cart) {
    my %work = %$item;
    my $product = Products->getByPkey($item->{productId});
    if ($product) {
      (my $comp_release = $product->{release}) =~ s/ .*//;
      (my $comp_expire = $product->{expire}) =~ s/ .*//;
      $comp_release le $today
	or do { push @msgs, "'$product->{title}' has not been released yet";
		next; };
      $today le $comp_expire
	or do { push @msgs, "'$product->{title}' has expired"; next; };
      $product->{listed} 
	or do { push @msgs, "'$product->{title}' not available"; next; };

      for my $col (@prodcols) {
	$work{$col} = $product->$col() unless exists $work{$col};
      }
      $work{price} = $product->price(user => scalar $req->siteuser);
      $work{extended_retailPrice} = $work{units} * $work{price};
      $work{extended_gst} = $work{units} * $work{gst};
      $work{extended_wholesale} = $work{units} * $work{wholesalePrice};
      
      push @newcart, \%work;
      push @$products, $product;
    }
  }

  # we don't use these for anything for now
  #if (@msgs) {
  #  @$rmsg = @msgs;
  #}

  return @newcart;
}

sub _fillout_order {
  my ($class, $req, $values, $items, $products, $rmsg, $how) = @_;

  my $session = $req->session;
  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  my $total = 0;
  my $total_gst = 0;
  my $total_wholesale = 0;
  for my $item (@$items) {
    $total += $item->{extended_retailPrice};
    $total_gst += $item->{extended_gst};
    $total_wholesale += $item->{extended_wholesale};
  }
  $values->{total} = $total;
  $values->{gst} = $total_gst;
  $values->{wholesaleTotal} = $total_wholesale;

  my $prompt_ship = $cfg->entry("shop", "shipping", 0);
  if ($prompt_ship) {
    my ($courier) = BSE::Shipping->get_couriers($cfg, $cgi->param("shipping_name"));
    my $country_code = bse_country_code($values->{delivCountry});
    if ($courier) {
      unless ($courier->can_deliver(country => $country_code,
				    suburb => $values->{delivSuburb},
				    postcode => $values->{delivPostCode})) {
	$cgi->param("courier", undef);
	$$rmsg =
	  "Can't use the selected courier ".
            "(". $courier->description(). ") for this order.";
	return;
      }
      my @parcels = BSE::Shipping->package_order($cfg, $values, $items);
      my $cost = $courier->calculate_shipping
	(
	 parcels => \@parcels,
	 country => $country_code,
	 suburb => $values->{delivSuburb},
	 postcode => $values->{delivPostCode},
	 products => $products,
	 items => $items,
       );
      if (!$cost and $courier->name() ne 'contact') {
	my $err = $courier->error_message();
	$$rmsg = "Error calculating shipping cost";
	$$rmsg .= ": $err" if $err;
	return;
      }
      $values->{shipping_method} = $courier->description();
      $values->{shipping_name} = $courier->name;
      $values->{shipping_cost} = $cost;
      $values->{shipping_trace} = $courier->trace;
      #$values->{delivery_in} = $courier->delivery_in();
      $values->{total} += $values->{shipping_cost};
    }
    else {
      # XXX: What to do?
      $$rmsg = "Error: no usable courier found.";
      return;
    }
  }

  my $cust_class = custom_class($cfg);

  eval {
    local $SIG{__DIE__};
    my %custom = %{$session->{custom}};
    $cust_class->order_save($cgi, $values, $items, $items, 
			    \%custom, $cfg);
    $session->{custom} = \%custom;
  };
  if ($@) {
    $$rmsg = $@;
    return;
  }

  $values->{total} += 
    $cust_class->total_extras($items, $items, 
			      $session->{custom}, $cfg, $how);

  my $affiliate_code = $session->{affiliate_code};
  defined $affiliate_code && length $affiliate_code
    or $affiliate_code = $cgi->param('affiliate_code');
  defined $affiliate_code or $affiliate_code = '';
  $values->{affiliate_code} = $affiliate_code;

  my $user = $req->siteuser;
  if ($user) {
    $values->{userId} = $user->{userId};
    $values->{siteuser_id} = $user->{id};
  }
  else {
    $values->{userId} = '';
    $values->{siteuser_id} = -1;
  }

  $values->{orderDate} = now_sqldatetime;

  # this should be hard to guess
  $values->{randomId} = md5_hex(time().rand().{}.$$);

  return 1;
}

sub action_prefix { '' }

sub req_location {
  my ($class, $req) = @_;

  require BSE::TB::Locations;
  my $cgi = $req->cgi;
  my $location_id = $cgi->param('location_id');
  my $location;
  if (defined $location_id && $location_id =~ /^\d+$/) {
    $location = BSE::TB::Locations->getByPkey($location_id);
    my %acts;
    %acts =
      (
       BSE::Util::Tags->static(\%acts, $req->cfg),
       location => [ \&tag_hash, $location ],
      );

    return $req->response('location', \%acts);
  }
  else {
    return
      {
       type=>BSE::Template->get_type($req->cfg, 'error'),
       content=>"Missing or invalid location_id",
      };
  }
}

sub _validate_add_by_id {
  my ($class, $req, $addid, $quantity, $error, $refresh_logon) = @_;

  my $product;
  if ($addid) {
    $product = BSE::TB::Seminars->getByPkey($addid);
    $product ||= Products->getByPkey($addid);
  }
  unless ($product) {
    $$error = "Cannot find product $addid";
    return;
  }

  return $class->_validate_add($req, $product, $quantity, $error, $refresh_logon);
}

sub _validate_add_by_code {
  my ($class, $req, $code, $quantity, $error, $refresh_logon) = @_;

  my $product;
  if (defined $code) {
    $product = BSE::TB::Seminars->getBy(product_code => $code);
    $product ||= Products->getBy(product_code => $code);
  }
  unless ($product) {
    $$error = "Cannot find product code $code";
    return;
  }

  return $class->_validate_add($req, $product, $quantity, $error, $refresh_logon);
}

sub _validate_add {
  my ($class, $req, $product, $quantity, $error, $refresh_logon) = @_;

  # collect the product options
  my @options;
  my @option_descs =  $product->option_descs($req->cfg);
  my @option_names = map $_->{name}, @option_descs;
  my @not_def;
  my $cgi = $req->cgi;
  for my $name (@option_names) {
    my $value = $cgi->param($name);
    push @options, $value;
    unless (defined $value) {
      push @not_def, $name;
    }
  }
  if (@not_def) {
    $$error = "Some product options (@not_def) not supplied";
    return;
  }
  
  # the product must be non-expired and listed
  (my $comp_release = $product->{release}) =~ s/ .*//;
  (my $comp_expire = $product->{expire}) =~ s/ .*//;
  my $today = now_sqldate();
  unless ($comp_release le $today) {
    $$error = "Product $product->{title} has not been released yet";
    return;
  }
  unless ($today le $comp_expire) {
    $$error = "Product $product->{title} has expired";
    return;
  }
  unless ($product->{listed}) {
    $$error = "Product $product->{title} not available";
    return;
  }
  
  # used to refresh if a logon is needed
  my $securlbase = $req->cfg->entryVar('site', 'secureurl');
  my $r = $securlbase . $ENV{SCRIPT_NAME} . "?add=1&id=$product->{id}";
  for my $opt_index (0..$#option_names) {
    $r .= "&$option_names[$opt_index]=".escape_uri($options[$opt_index]);
  }
  
  my $user = $req->siteuser;
  # need to be logged on if it has any subs
  if ($product->{subscription_id} != -1) {
    if ($user) {
      my $sub = $product->subscription;
      if ($product->is_renew_sub_only) {
	unless ($user->subscribed_to_grace($sub)) {
	  $$error = "The product $product->{title} can only be used to renew your subscription to $sub->{title} and you are not subscribed nor within the renewal grace period";
	  return;
	}
      }
      elsif ($product->is_start_sub_only) {
	if ($user->subscribed_to_grace($sub)) {
	  $$error = "The product $product->{title} can only be used to start your subscription to $sub->{title} and you are already subscribed or within the grace period";
	  return;
	}
      }
    }
    else {
      $$refresh_logon = 
	[  "You must be logged on to add this product to your cart", 
	   'prodlogon', $r ];
      return;
    }
  }
  if ($product->{subscription_required} != -1) {
    my $sub = $product->subscription_required;
    if ($user) {
      unless ($user->subscribed_to($sub)) {
	$$error = "You must be subscribed to $sub->{title} to purchase this product";
	return;
      }
    }
    else {
      # we want to refresh back to adding the item to the cart if possible
      $$refresh_logon = 
	[ "You must be logged on and subscribed to $sub->{title} to add this product to your cart",
	 'prodlogonsub', $r ];
      return;
    }
  }

  # we need a natural integer quantity
  unless ($quantity =~ /^\d+$/ && $quantity > 0) {
    $$error = "Invalid quantity";
    return;
  }

  my %extras;
  if ($product->isa('BSE::TB::Seminar')) {
    # you must be logged on to add a seminar
    unless ($user) {
      $$refresh_logon = 
	[ "You must be logged on to add seminars to your cart", 
	  'seminarlogon', $r ];
      return;
    }

    # get and validate the session
    my $session_id = $cgi->param('session_id');
    unless (defined $session_id) {
      $$error = "Please select a session when adding a seminar";
      return;
    }
    
    unless ($session_id =~ /^\d+$/) {
      $$error = "Invalid session_id supplied";
      return;
    }
      
    require BSE::TB::SeminarSessions;
    my $session = BSE::TB::SeminarSessions->getByPkey($session_id);
    unless ($session) {
      $$error = "Unknown session id supplied";
      return;
    }
    unless ($session->{seminar_id} == $product->{id}) {
      $$error = "Session not for this seminar";
      return;
    }

    # check if the user is already booked for this session
    if (grep($_ == $session_id, $user->seminar_sessions_booked($product->{id}))) {
      $$error = "You are already booked for this session";
      return;
    }

    $extras{session_id} = $session_id;
  }

  return ( $product, \@options, \%extras );
}

sub _add_refresh {
  my ($refresh, $req, $started_empty) = @_;

  my $cfg = $req->cfg;
  my $cookie_domain = $cfg->entry('basic', 'cookie_domain');
  if ($started_empty && !$cookie_domain) {
    my $base_url = $cfg->entryVar('site', 'url');
    my $secure_url = $cfg->entryVar('site', 'secureurl');
    if ($base_url ne $secure_url) {
      my $debug = $cfg->entryBool('debug', 'logon_cookies', 0);

      # magical refresh time
      # which host are we on?
      # first get info about the 2 possible hosts
      my ($baseprot, $basehost, $baseport) = 
	$base_url =~ m!^(\w+)://([\w.-]+)(?::(\d+))?!;
      $baseport ||= $baseprot eq 'http' ? 80 : 443;
      print STDERR "Base: prot: $baseprot  Host: $basehost  Port: $baseport\n"
	if $debug;
      
      #my ($secprot, $sechost, $secport) = 
      #  $securl =~ m!^(\w+)://([\w.-]+)(?::(\d+))?!;

      my $onbase = 1;
      # get info about the current host
      my $port = $ENV{SERVER_PORT} || 80;
      my $ishttps = exists $ENV{HTTPS} || exists $ENV{SSL_CIPHER};
      print STDERR "\$ishttps: $ishttps\n" if $debug;
      my $protocol = $ishttps ? 'https' : 'http';

      if (lc $ENV{SERVER_NAME} ne lc $basehost
	  || lc $protocol ne $baseprot
	  || $baseport != $port) {
	print STDERR "not on base host ('$ENV{SERVER_NAME}' cmp '$basehost' '$protocol cmp '$baseprot'  $baseport cmp $port\n" if $debug;
	$onbase = 0;
      }
      my $url = $onbase ? $secure_url : $base_url;
      my $finalbase = $onbase ? $base_url : $secure_url;
      $refresh = $finalbase . $refresh unless $refresh =~ /^\w+:/;
      print STDERR "Heading to $url to setcookie\n" if $debug;
      $url .= "/cgi-bin/user.pl?setcookie=".$req->session->{_session_id};
      $url .= "&r=".CGI::escape($refresh);
      return BSE::Template->get_refresh($url, $cfg);
    }
  }

  return BSE::Template->get_refresh($refresh, $cfg);
}

sub _same_options {
  my ($left, $right) = @_;

  for my $index (0 .. $#$left) {
    my $left_value = $left->[$index];
    my $right_value = $right->[$index];
    defined $right_value
      or return;
    $left_value eq $right_value
      or return;
  }

  return 1;
}

sub _paypal_order {
  my ($self, $req, $rmsg) = @_;

  my $id = $req->cgi->param("order");
  unless ($id) {
    $$rmsg = $req->catmsg("msg:bse/shop/paypal/noorderid");
    return;
  }
  my ($order) = BSE::TB::Orders->getBy(randomId => $id);
  unless ($order) {
    $$rmsg = $req->catmsg("msg:bse/shop/paypal/unknownorderid");
    return;
  }

  return $order;
}

=item paypalret

Handles PayPal returning control.

Expects:

=over

=item *

order - the randomId of the order

=item *

token - paypal token we originally supplied to paypal.  Supplied by
PayPal.

=item *

PayerID - the paypal user who paid the order.  Supplied by PayPal.

=back

=cut

sub req_paypalret {
  my ($self, $req) = @_;

  require BSE::PayPal;
  BSE::PayPal->configured
      or return $self->req_cart($req, { _ => "msg:bse/shop/paypal/unconfigured" });

  my $msg;
  my $order = $self->_paypal_order($req, \$msg)
    or return $self->req_show_payment($req, { _ => $msg });

  $order->complete
    and return $self->req_cart($req, { _ => "msg:bse/shop/paypal/alreadypaid" });

  unless (BSE::PayPal->pay_order(req => $req,
				 order => $order,
				 msg => \$msg)) {
    return $self->req_show_payment($req, { _ => $msg });
  }

  $self->_finish_order($req, $order);

  return $req->get_refresh($req->user_url(shop => "orderdone"));
}

sub req_paypalcan {
  my ($self, $req) = @_;

  require BSE::PayPal;
  BSE::PayPal->configured
      or return $self->req_cart($req, { _ => "msg:bse/shop/paypal/unconfigured" });

  my $msg;
  my $order = $self->_paypal_order($req, \$msg)
    or return $self->req_show_payment($req, { _ => $msg });

  $req->flash("msg:bse/shop/paypal/cancelled");

  my $url = $req->user_url(shop => "show_payment");
  return $req->get_refresh($url);
}

1;
