package BSE::UI::Shop;
use strict;
use base 'BSE::UI::Dispatch';
use DevHelp::HTML;
use BSE::Util::SQL qw(now_sqldate now_sqldatetime);
use BSE::Shop::Util qw(need_logon shop_cart_tags payment_types nice_options cart_item_opts basic_tags);
use BSE::CfgInfo qw(custom_class credit_card_class);
use BSE::TB::Orders;
use BSE::TB::OrderItems;
use BSE::Mail;
use BSE::Util::Tags qw(tag_error_img);
use Products;
use DevHelp::Validate qw(dh_validate dh_validate_hash);

use constant PAYMENT_CC => 0;
use constant PAYMENT_CHEQUE => 1;
use constant PAYMENT_CALLME => 2;

my %actions =
  (
   add => 1,
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
  );

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

my %rev_field_map = reverse %field_map;

sub actions { \%actions }

sub default_action { 'cart' }

sub other_action {
  my ($class, $cgi) = @_;

  for my $key ($cgi->param()) {
    if ($key =~ /^delete_(\d+)$/) {
      return ( remove_item => $1 );
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

  my %acts;
  %acts =
    (
     $cust_class->cart_actions(\%acts, \@cart, \@cart_prods, \%custom_state, 
			       $req->cfg),
     shop_cart_tags(\%acts, \@items, \@cart_prods, $req->session, $req->cgi, 
		    $req->cfg, 'cart'),
     basic_tags(\%acts),
     msg => $msg,
    );
  $req->session->{custom} = \%custom_state;
  $req->session->{order_info_confirmed} = 0;

  return $req->response('cart', \%acts);
}

sub req_add {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;

  my $addid = $cgi->param('id');
  $addid ||= '';
  my $quantity = $cgi->param('quantity');
  $quantity ||= 1;
  my $product;
  $product = Products->getByPkey($addid) if $addid;
  $product or 
    return $class->req_cart($req, "Cannot find product $addid"); # oops

  # collect the product options
  my @options;
  my @opt_names = split /,/, $product->{options};
  my @not_def;
  for my $name (@opt_names) {
    my $value = $cgi->param($name);
    push @options, $value;
    unless (defined $value) {
      push @not_def, $name;
    }
  }
  @not_def
    and return $class->req_cart($req, "Some product options (@not_def) not supplied");
  my $options = join(",", @options);
  
  # the product must be non-expired and listed
  (my $comp_release = $product->{release}) =~ s/ .*//;
  (my $comp_expire = $product->{expire}) =~ s/ .*//;
  my $today = now_sqldate();
  $comp_release le $today
    or return $class->req_cart($req, "Product has not been released yet");
  $today le $comp_expire
    or return $class->req_cart($req, "Product has expired");
  $product->{listed} or return $class->req_cart($req, "Product not available");
  
  # used to refresh if a logon is needed
  my $securlbase = $req->cfg->entryVar('site', 'secureurl');
  my $r = $securlbase . $ENV{SCRIPT_NAME} . "?add=1&id=$addid";
  for my $opt_index (0..$#opt_names) {
    $r .= "&$opt_names[$opt_index]=".escape_uri($options[$opt_index]);
  }
  
  my $user = $req->siteuser;
  # need to be logged on if it has any subs
  if ($product->{subscription_id} != -1) {
    if ($user) {
      my $sub = $product->subscription;
      if ($product->is_renew_sub_only) {
	unless ($user->subscribed_to_grace($sub)) {
	  return show_cart("This product can only be used to renew your subscription to $sub->{title} and you are not subscribed nor within the renewal grace period");
	}
      }
      elsif ($product->is_start_sub_only) {
	if ($user->subscribed_to_grace($sub)) {
	  return show_cart("This product can only be used to start your subscription to $sub->{title} and you are already subscribed or within the grace period");
	}
      }
    }
    else {
      return $class->_refresh_logon
	($req, "You must be logged on to add this product to your cart", 
	 'prodlogon', $r);
    }
  }
  if ($product->{subscription_required} != -1) {
    my $sub = $product->subscription_required;
    if ($user) {
      unless ($user->subscribed_to($sub)) {
	return $class->req_cart($req, "You must be subscribed to $sub->{title} to purchase this product");
	return;
      }
    }
    else {
      # we want to refresh back to adding the item to the cart if possible
      return $class->_refresh_logon
	($req, "You must be logged on and subscribed to $sub->{title} to add this product to your cart",
	 'prodlogonsub', $r);
    }
  }

  # we need a natural integer quantity
  $quantity =~ /^\d+$/
    or return $class->req_cart($req, "Invalid quantity");

  $req->session->{cart} ||= [];
  my @cart = @{$req->session->{cart}};
 
  # if this is is already present, replace it
  @cart = grep { $_->{productId} ne $addid || $_->{options} ne $options } 
    @cart;
  push @cart, 
    { 
     productId => $addid, 
     units => $quantity, 
     price=>$product->{retailPrice},
     options=>$options 
    };

  $req->session->{cart} = \@cart;
  $req->session->{order_info_confirmed} = 0;
  
  return $class->req_cart($req);
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

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     shop_cart_tags(\%acts, \@items, \@cart_prods, $req->session, $req->cgi, 
		    $cfg, 'checkout'),
     basic_tags(\%acts),
     message => $message,
     msg => $message,
     old => 
     sub { 
       my $value;

       if ($olddata) {
	 $value = $cgi->param($_[0]);
	 unless (defined $value) {
	   $value = $user->{$_[0]}
	     if $user;
	 }
       }
       elsif ($order_info && defined $order_info->{$_[0]}) {
	 $value = $order_info->{$_[0]};
       }
       else {
	 my $field = $_[0];
	 $rev_field_map{$field} and $field = $rev_field_map{$field};
	 $value = $user && defined $user->{$field} ? $user->{$field} : '';
       }
       
       defined $value or $value = '';
       escape_html($value);
     },
     $cust_class->checkout_actions(\%acts, \@cart, \@cart_prods, 
				   \%custom_state, $req->cgi, $cfg),
     ifUser => defined $user,
     user => $user ? [ \&tag_hash, $user ] : '',
     affiliate_code => escape_html($affiliate_code),
     error_img => [ \&tag_error_img, $cfg, $errors ],
    );
  $req->session->{custom} = \%custom_state;

  return $req->response('checkoutnew', \%acts);
}

sub req_checkupdate {
  my ($class, $req) = @_;

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
  my @cart = @{$req->session->{cart}};
  if ($index >= 0 && $index < @cart) {
    splice(@cart, $index, 1);
  }
  $req->session->{cart} = \@cart;
  $req->session->{order_info_confirmed} = 0;

  return BSE::Template->get_refresh($ENV{SCRIPT_NAME}, $req->cfg);
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

  # some basic validation, in case the user switched off javascript
  my $cust_class = custom_class($cfg);

  my %fields = BSE::TB::Order->valid_fields($cfg);
  my %rules = BSE::TB::Order->valid_rules($cfg);
  
  my %errors;
  my %values;
  for my $name (keys %fields) {
    ($values{$name}) = $cgi->param($name);
  }

  my @required = 
    $cust_class->required_fields($cgi, $req->session->{custom}, $cfg);

  for my $name (@required) {
    $field_map{$name} and $name = $field_map{$name};

    $fields{$name}{required} = 1;
  }

  dh_validate_hash(\%values, \%errors, { rules=>\%rules, fields=>\%fields },
		   $cfg, 'Shop Order Validation');
  keys %errors
    and return $class->req_checkout($req, \%errors, 1);

  $class->_fillout_order($req, \%values, \@items, \$msg, 'payment')
    or return $class->req_checkout($req, $msg, 1);

  $req->session->{order_info} = \%values;
  $req->session->{order_info_confirmed} = 1;

  return BSE::Template->get_refresh("$ENV{SCRIPT_NAME}?a_show_payment=1", $req->cfg);
}

sub req_show_payment {
  my ($class, $req, $errors) = @_;

  $req->session->{order_info_confirmed}
    or return $class->req_checkout($req, 'Please proceed via the checkout page');

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  $errors ||= {};
  my $msg = $req->message($errors);

  my $order_values = $req->session->{order_info}
    or return $class->req_checkout($req, "You need to enter order information first");

  my @pay_types = payment_types($cfg);
  my @payment_types = map $_->{id}, grep $_->{enabled}, @pay_types;
  my %types_by_name = map { $_->{name} => $_->{id} } @pay_types;
  @payment_types or @payment_types = ( PAYMENT_CALLME );
  @payment_types = sort { $a <=> $b } @payment_types;
  my %payment_types = map { $_=> 1 } @payment_types;
  my $payment;
  $errors and $payment = $cgi->param('paymentType');
  defined $payment or $payment = $payment_types[0];

  my @products;
  my @items = $class->_build_items($req, \@products);

  my %acts;
  %acts =
    (
     basic_tags(\%acts),
     message => $msg,
     msg => $msg,
     order => [ \&tag_hash, $order_values ],
     shop_cart_tags(\%acts, \@items, \@products, $req->session, $req->cgi,
		    $req->cfg, 'payment'),
     ifMultPaymentTypes => @payment_types > 1,
     checkedPayment => [ \&tag_checkedPayment, $payment, \%types_by_name ],
     ifPayments => [ \&tag_ifPayments, \@payment_types, \%types_by_name ],
     error_img => [ \&tag_error_img, $cfg, $errors ],
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
  );

sub req_payment {
  my ($class, $req, $errors) = @_;

  $req->session->{order_info_confirmed}
    or return $class->req_checkout($req, 'Please proceed via the checkout page');

  my $order_values = $req->session->{order_info}
    or return $class->req_checkout($req, "You need to enter order information first");


  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $session = $req->session;

  my @pay_types = payment_types($cfg);
  my @payment_types = map $_->{id}, grep $_->{enabled}, @pay_types;
  my %pay_types = map { $_->{id} => $_ } @pay_types;
  my %types_by_name = map { $_->{name} => $_->{id} } @pay_types;
  @payment_types or @payment_types = ( PAYMENT_CALLME );
  @payment_types = sort { $a <=> $b } @payment_types;
  my %payment_types = map { $_=> 1 } @payment_types;

  my $paymentType = $cgi->param('paymentType');
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

  my @products;
  my @items = $class->_build_items($req, \@products);
  
  for my $field (@required) {
    unless ($nostore{$field}) {
      ($order_values->{$field}) = $cgi->param($field);
    }
  }

  $order_values->{filled} = 0;
  $order_values->{paidFor} = 0;

  my $cust_class = custom_class($req->cfg);
  eval {
    my %custom = %{$session->{custom}};
    $cust_class->order_save($cgi, $order_values, \@items, \@products, 
			    \%custom, $cfg);
    $session->{custom} = \%custom;
  };
  if ($@) {
    return $class->req_checkout($req, $@, 1);
  }

  my @columns = BSE::TB::Order->columns;
  my %columns; 
  @columns{@columns} = @columns;

  for my $col (@columns) {
    defined $order_values->{$col} or $order_values->{$col} = '';
  }

  $order_values->{paymentType} = $paymentType;

  my @data = @{$order_values}{@columns};
  shift @data;
  my $order = BSE::TB::Orders->add(@data)
    or die "Cannot add order";

  my @dbitems;
  my %subscribing_to;
  my @item_cols = BSE::TB::OrderItem->columns;
  for my $row_num (0..$#items) {
    my $item = $items[$row_num];
    my $product = $products[$row_num];
    $item->{orderId} = $order->{id};
    $item->{max_lapsed} = 0;
    if ($product->{subscription_id} != -1) {
      my $sub = $product->subscription;
      $item->{max_lapsed} = $sub->{max_lapsed} if $sub;
    }
    my @data = @{$item}{@item_cols};
    
    shift @data;
    push(@dbitems, BSE::TB::OrderItems->add(@data));

    my $sub = $product->subscription;
    if ($sub) {
      $subscribing_to{$sub->{text_id}} = $sub;
    }
  }
  
  my $ccprocessor = $cfg->entry('shop', 'cardprocessor');
  if ($paymentType == PAYMENT_CC && $ccprocessor) {
    my $cc_class = credit_card_class($cfg);

    $order->{ccOnline} = 1;

    my $ccNumber = $cgi->param('cardNumber');
    my $ccExpiry = $cgi->param('cardExpiry');
    $ccExpiry =~ m!^(\d+)\D(\d+)$! or die;
    my ($month, $year) = ($1, $2);
    $year > 2000 or $year += 2000;
    my $expiry = sprintf("%04d%02d", $year, $month);
    my $verify = $cgi->param('cardVerify');
    defined $verify or $verify = '';
    my $result = $cc_class->payment(orderno=>$order->{id},
				    amount => $order->{total},
				    cardnumber => $ccNumber,
				    expirydate => $expiry,
				    cvv => $verify,
				    ipaddress => $ENV{REMOTE_ADDR});
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
    $order->{paidFor}	    = 1;
    $order->save;
  }

  # set the order displayed by orderdone
  $session->{order_completed} = $order->{id};
  $session->{order_completed_at} = time;

  my $noencrypt = $cfg->entryBool('shop', 'noencrypt', 0);
  $class->_send_order($req, $order, \@dbitems, \@products, $noencrypt,
		      \%subscribing_to);

  # empty the cart ready for the next order
  delete @{$session}{qw/order_info order_info_confirmed cart order_work/};

  return BSE::Template->get_refresh("$ENV{SCRIPT_NAME}?a_orderdone=1", $req->cfg);
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

  my $cust_class = custom_class($req->cfg);

  my @pay_types = payment_types($cfg);
  my @payment_types = map $_->{id}, grep $_->{enabled}, @pay_types;
  my %pay_types = map { $_->{id} => $_ } @pay_types;
  my %types_by_name = map { $_->{name} => $_->{id} } @pay_types;

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     $cust_class->purchase_actions(\%acts, \@items, \@products, 
				   $session->{custom}, $cfg),
     BSE::Util::Tags->static(\%acts, $cfg),
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
     item=> sub { escape_html($items[$item_index]{$_[0]}); },
     product => 
     sub { 
       my $value = $products[$item_index]{$_[0]};
       defined $value or $value = '';

       escape_html($value);
     },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $items[$item_index]{units} * $items[$item_index]{$what};
     },
     order => sub { escape_html($order->{$_[0]}) },
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
     option => sub { escape_html($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
     ifPayment => [ \&tag_ifPayment, $order->{paymentType}, \%types_by_name ],
     #ifSubscribingTo => [ \&tag_ifSubscribingTo, \%subscribing_to ],
    );
  for my $type (@pay_types) {
    my $id = $type->{id};
    my $name = $type->{name};
    $acts{"if${name}Payment"} = $order->{paymentType} == $id;
  }

  return $req->response('checkoutfinal', \%acts);
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

sub req_purchase {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msg;
  $class->_validate_cfg($req, \$msg)
    or return $class->req_cart($req, $msg);
    
  # some basic validation, in case the user switched off javascript
  my $cust_class = custom_class($cfg);
  my @required = 
    $cust_class->required_fields($cgi, $session->{custom}, $cfg);

  my $noencrypt = $cfg->entryBool('shop', 'noencrypt', 0);

  my @pay_types = payment_types($cfg);
  my %pay_types = map { $_->{id} => $_ } @pay_types;
  my %types_by_name = map { $_->{name} => $_->{id} } @pay_types;
  #use Data::Dumper;
  #print STDERR Dumper \%pay_types;
  my @payment_types = map $_->{id}, grep $_->{enabled}, @pay_types;
  if ($noencrypt) {
    @payment_types = grep $_ ne PAYMENT_CC, @payment_types;
    @payment_types or @payment_types = ( PAYMENT_CALLME );
  }
  else {
    @payment_types or @payment_types = ( PAYMENT_CC );
  }
  @payment_types = sort { $a <=> $b } @payment_types;
  my %payment_types = map { $_=> 1 } @payment_types;

  my $paymentType = $cgi->param('paymentType');
  defined $paymentType or $paymentType = $payment_types[0];
  $payment_types{$paymentType}
    or return $class->req_checkout($req, "Invalid payment type", 1);

  push @required, @{$pay_types{$paymentType}{require}};

  for my $field (@required) {
    my $display = $cfg->entry('shop', "display_$field", $field);
    defined($cgi->param($field)) && length($cgi->param($field))
      or return $class->req_checkout($req, "Field $display is required", 1);
  }
  defined($cgi->param('email')) && $cgi->param('email') =~ /.\@./
    or return $class->req_checkout($req, "Please enter a valid email address", 1);
  if ($paymentType == PAYMENT_CC) {
    defined($cgi->param('cardNumber')) && $cgi->param('cardNumber') =~ /^\d+$/
      or return $class->req_checkout($req, "Please enter a credit card number", 1);
  }

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
  my @cart = @{$session->{cart}};
  @cart or return $class->req_cart($req, 'You have no items in your shopping cart');

  # so we can quickly check for columns
  my @columns = BSE::TB::Order->columns;
  my %columns; 
  @columns{@columns} = @columns;

  for my $field ($req->param()) {
    $order{$field_map{$field} || $field} = $req->param($field)
      unless $nostore{$field};
  }

  my $ccNumber = $req->param('cardNumber');
  defined $ccNumber or $ccNumber = '';
  my $ccExpiry = $req->param('cardExpiry');
  defined $ccExpiry or $ccExpiry = '';
  my $affiliate_code = $session->{affiliate_code};
  defined $affiliate_code && length $affiliate_code
    or $affiliate_code = $cgi->param('affiliate_code');
  defined $affiliate_code or $affiliate_code = '';
  $order{affiliate_code} = $affiliate_code;

  use Digest::MD5 'md5_hex';
  $ccNumber =~ tr/0-9//cd;
  $order{ccNumberHash} = md5_hex($ccNumber);
  $order{ccExpiryHash} = md5_hex($ccExpiry);

  # work out totals
  $order{total} = 0;
  $order{gst} = 0;
  $order{wholesale} = 0;
  $order{shipping_cost} = 0;
  my @products;
  my $today = now_sqldate();
  for my $item (@cart) {
    my $product = Products->getByPkey($item->{productId});
    # double check that it's still a valid product
    if (!$product) {
      return $class->req_cart($req, "Product $item->{productId} not found");
    }
    else {
      (my $comp_release = $product->{release}) =~ s/ .*//;
      (my $comp_expire = $product->{expire}) =~ s/ .*//;
      $comp_release le $today
	or return $class->req_cart($req, "'$product->{title}' has not been released yet");
      $today le $comp_expire
	or return $class->req_cart("'$product->{title}' has expired");
      $product->{listed} 
	or return $class->req_cart("'$product->{title}' not available");
    }
    push(@products, $product); # used in page rendering
    @$item{qw/price wholesalePrice gst/} = 
      @$product{qw/retailPrice wholesalePrice gst/};
    $order{total} += $item->{price} * $item->{units};
    $order{wholesale} += $item->{wholesalePrice} * $item->{units};
    $order{gst} += $item->{gst} * $item->{units};
  }

  if (my ($msg, $id) = $class->_need_logon($req, \@cart, \@products)) {
    return $class->_refresh_logon($req, $msg, $id);
  }

  $order{orderDate} = now_sqldatetime;
  $order{paymentType} = $paymentType;
  ++$session->{changed};

  # blank anything else
  for my $column (@columns) {
    defined $order{$column} or $order{$column} = '';
  }
  # make sure the user can't set these behind our backs
  $order{filled} = 0;
  $order{paidFor} = 0;

  my $user = $req->siteuser;
  if ($user) {
    $order{userId} = $user->{userId};
    $order{siteuser_id} = $user->{id};
  }
  else {
    $order{userId} = '';
    $order{siteuser_id} = -1;
  }

  # this should be hard to guess
  $order{randomId} = md5_hex(time().rand().{}.$$);

  # check if a customizer has anything to do
  # if it sets shipping cost it must also update the total
  eval {
    my %custom = %{$session->{custom}};
    $cust_class->order_save($cgi, \%order, \@cart, \@products, 
			    \%custom, $cfg);
    $session->{custom} = \%custom;
  };
  if ($@) {
    return $class->req_checkout($req, $@, 1);
  }

  $order{total} += $cust_class->total_extras(\@cart, \@products, 
					     $session->{custom}, $cfg, 'final');

  my %subscribing_to;

  # load up the database
  my @data = @order{@columns};
  shift @data; # lose the dummy id
  my $order = BSE::TB::Orders->add(@data)
    or die "Cannot add order";
  my @items;
  my @item_cols = BSE::TB::OrderItem->columns;
  my @prod_xfer = qw/title summary subscription_id subscription_period/;
  for my $row_num (0..$#cart) {
    my $row = $cart[$row_num];
    my $product = $products[$row_num];
    $row->{orderId} = $order->{id};

    # store product data too
    @$row{@prod_xfer} = @{$product}{@prod_xfer};

    # store the lapsed value, this prevents future changes causing
    # variation of the expiry date
    $row->{max_lapsed} = 0;
    if ($product->{subscription_id} != -1) {
      my $sub = $product->subscription;
      $row->{max_lapsed} = $sub->{max_lapsed} if $sub;
    }

    my @data = @$row{@item_cols};
    
    shift @data;
    push(@items, BSE::TB::OrderItems->add(@data));

    my $sub = $product->subscription;
    if ($sub) {
      $subscribing_to{$sub->{text_id}} = $sub;
    }
  }

  if ($user) {
    $user->recalculate_subscriptions($cfg);
  }

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     $cust_class->purchase_actions(\%acts, \@items, \@products, 
				   $session->{custom}, $cfg),
     BSE::Util::Tags->static(\%acts, $cfg),
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
     item=> sub { escape_html($items[$item_index]{$_[0]}); },
     product => 
     sub { 
       my $value = $products[$item_index]{$_[0]};
       defined $value or $value = '';

       escape_html($value);
     },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $items[$item_index]{units} * $items[$item_index]{$what};
     },
     order => sub { escape_html($order->{$_[0]}) },
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
     option => sub { escape_html($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
     ifPayment => [ \&tag_ifPayments, $order->{paymentType}, \%types_by_name ],
     #ifSubscribingTo => [ \&tag_ifSubscribingTo, \%subscribing_to ],
    );
  for my $type (@pay_types) {
    my $id = $type->{id};
    my $name = $type->{name};
    $acts{"if${name}Payment"} = $order->{paymentType} == $id;
  }
  send_order($order, \@items, \@products, $noencrypt, \%subscribing_to);
  $session->{cart} = []; # empty the cart

  return req->response('checkoutfinal', \%acts);
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
  my ($class, $req, $order, $items, $products, $noencrypt, 
      $subscribing_to) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  my $crypto_class = $Constants::SHOP_CRYPTO;
  my $signing_id = $Constants::SHOP_SIGNING_ID;
  my $pgp = $Constants::SHOP_PGP;
  my $pgpe = $Constants::SHOP_PGPE;
  my $gpg = $Constants::SHOP_GPG;
  my $passphrase = $Constants::SHOP_PASSPHRASE;
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

  my $item_index = -1;
  my @options;
  my $option_index;
  my %acts;
  %acts =
    (
     %extras,
     custom_class($cfg)
     ->order_mail_actions(\%acts, $order, $items, $products, 
			  $session->{custom}, $cfg),
     BSE::Util::Tags->static(\%acts, $cfg),
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
     product => 
     sub { 
       my $value = $products->[$item_index]{$_[0]};
       defined($value) or $value = '';
       $value;
     },
     order => sub { $order->{$_[0]} },
     extended => 
     sub {
       $items->[$item_index]{units} * $items->[$item_index]{$_[0]};
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
     option => sub { escape_html($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
     with_wrap => \&tag_with_wrap,
     ifSubscribingTo => [ \&tag_ifSubscribingTo, $subscribing_to ],
    );

  my $mailer = BSE::Mail->new(cfg=>$cfg);
  # ok, send some email
  my $confirm = BSE::Template->get_page('mailconfirm', $cfg, \%acts);
  my $email_order = $cfg->entryBool('shop', 'email_order', $Constants::SHOP_EMAIL_ORDER);
  if ($email_order) {
    unless ($noencrypt) {
      $acts{cardNumber} = $cgi->param('cardNumber');
      $acts{cardExpiry} = $cgi->param('cardExpiry');
    }
    my $ordertext = BSE::Template->get_page('mailorder', $cfg, \%acts);
    
    my $send_text;
    if ($noencrypt) {
      $send_text = $ordertext;
    }
    else {
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

      $send_text = $encrypter->encrypt($recip, $ordertext, %opts )
	or die "Cannot encrypt ", $encrypter->error;
    }
    $mailer->send(to=>$toEmail, from=>$from, subject=>'New Order '.$order->{id},
		  body=>$send_text)
      or print STDERR "Error sending order to admin: ",$mailer->errstr,"\n";
  }
  $mailer->send(to=>$order->{emailAddress}, from=>$from,
		subject=>$subject . " " . localtime,
		body=>$confirm)
    or print STDERR "Error sending order to customer: ",$mailer->errstr,"\n";
}

sub tag_with_wrap {
  my ($args, $text) = @_;

  my $margin = $args =~ /^\d+$/ && $args > 30 ? $args : 70;

  require Text::Wrap;
  # do it twice to prevent a warning
  $Text::Wrap::columns = $margin;
  $Text::Wrap::columns = $margin;

  return Text::Wrap::fill('', '', split /\n/, $text);
}

sub _refresh_logon {
  my ($class, $req, $msg, $msgid, $r) = @_;

  my $securlbase = $req->cfg->entryVar('site', 'secureurl');
  my $url = $securlbase."/cgi-bin/user.pl";

  $r ||= $securlbase."/cgi-bin/shop.pl?checkout=1";
  
  my %parms;
  $parms{r} = $r;
  $parms{message} = $msg if $msg;
  $parms{mid} = $msgid if $msgid;
  $url .= "?" . join("&", map "$_=".escape_uri($parms{$_}), keys %parms);
  
  return BSE::Template->get_refresh($url, $req->cfg);
}

sub _need_logon {
  my ($class, $req, $cart, $cart_prods) = @_;

  return need_logon($req->cfg, $cart, $cart_prods, $req->session, $req->cgi);
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
	$work{$col} = $product->{$col} unless exists $work{$col};
      }
      $work{extended_retailPrice} = $work{units} * $work{retailPrice};
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
  my ($class, $req, $values, $items, $rmsg, $how) = @_;

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
  $values->{wholesale} = $total_wholesale;
  $values->{shipping_cost} = 0;

  my $cust_class = custom_class($cfg);

  # if it sets shipping cost it must also update the total
  eval {
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
  $values->{randomId} ||= md5_hex(time().rand().{}.$$);

  return 1;
}

sub action_prefix { '' }

1;