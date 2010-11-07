package BSE::Shop::Util;
use strict;
use vars qw(@ISA @EXPORT_OK);
@ISA = qw/Exporter/;
@EXPORT_OK = qw/shop_cart_tags cart_item_opts nice_options shop_nice_options
                total shop_total load_order_fields basic_tags need_logon
                payment_types order_item_opts
 PAYMENT_CC PAYMENT_CHEQUE PAYMENT_CALLME PAYMENT_MANUAL PAYMENT_PAYPAL/;


our %EXPORT_TAGS =
  (
   payment => [ grep /^PAYMENT_/, @EXPORT_OK ],
  );

use Constants qw/:shop/;
use BSE::Util::SQL qw(now_sqldate);
use BSE::Util::Tags;
use BSE::CfgInfo qw(custom_class);
use Carp 'confess';
use BSE::Util::HTML qw(escape_html);

use constant PAYMENT_CC => 0;
use constant PAYMENT_CHEQUE => 1;
use constant PAYMENT_CALLME => 2;
use constant PAYMENT_MANUAL => 3;
use constant PAYMENT_PAYPAL => 4;

=item shop_cart_tags($acts, $cart, $cart_prods, $req, $stage)

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
  my ($acts, $cart, $cart_prods, $req, $stage) = @_;

  my $cfg = $req->cfg;
  my $q = $req->cgi;
  $cfg or confess "No config";
  $cfg->isa("BSE::Cfg") or confess "Not a config";

  my $item_index;
  my $option_index;
  my @options;
  my $sem_session;
  my $location;
  my $item;
  my $product;
  my $have_sale_files;
  return
    (
     $req->dyn_user_tags(),
     iterate_items_reset => sub { $item_index = -1 },
     iterate_items => 
     sub { 
       if (++$item_index < @$cart) {
	 $option_index = -1;
	 @options = cart_item_opts($req,
				   $cart->[$item_index], 
				   $cart_prods->[$item_index]);
	 undef $sem_session;
	 undef $location;
	 $item = $cart->[$item_index];
	 $product = $cart_prods->[$item_index];
	 return 1;
       }
       undef $item;
       undef $sem_session;
       undef $product;
       undef $location;
       return 0;
     },
     item => 
     sub { 
       my $value = $cart->[$item_index]{$_[0]};
       defined($value) or $value = $cart_prods->[$item_index]{$_[0]};
       defined($value) or $value = '';
       if ($_[0] eq 'link') {
	 $value = $cart_prods->[$item_index]->link,
       }
       if ($_[0] eq 'link' && $value !~ /^\w+:/) {
	 $value = $req->cfg->entryErr('site', 'url') . $value;
       }
       escape_html($value);
     },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $cart->[$item_index]{units} * $cart_prods->[$item_index]{$what};
     },
     index => sub { $item_index },
     total => 
     sub { total($cart, $cart_prods, $req->session->{custom}, $cfg, $stage) },
     count => sub { scalar @$cart },
     iterate_options_reset => sub { $option_index = -1 },
     iterate_options => sub { ++$option_index < @options },
     option => sub { escape_html($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
     session => [ \&tag_session, \$item, \$sem_session ],
     location => [ \&tag_location, \$item, \$location ],
     ifHaveSaleFiles => [ \&tag_ifHaveSaleFiles, \$have_sale_files, $cart_prods ],
     custom_class($cfg)
     ->checkout_actions($acts, $cart, $cart_prods, $req->session->{custom}, $q, $cfg),
    );  
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
  
  if (length $order_item->{options}) {
    my @values = split /,/, $order_item->options;
    return map
      +{
	id => $_->{id},
	value => $_->{value},
	desc => $_->{desc},
	label => $_->{display},
       }, $product->option_descs($req->cfg, \@values);
  }
  else {
    my @options = $order_item->option_list;
    return map
      +{
	id => $_->original_id,
	value => $_->value,
	desc => $_->name,
	label => $_->display
       }, @options;
  }
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
  my ($wantcard, $q, $order, $req, $cart_prods, $error) = @_;

  my $session = $req->session;
  my $cfg = $req->cfg;

  my $cust_class = custom_class($cfg);

  my @required = $cust_class->required_fields($q, $session->{custom});
  push(@required, qw(cardHolder cardExpiry)) if $wantcard;
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

sub need_logon {
  my ($req, $cart, $cart_prods) = @_;

  defined $req or confess "No cgi parameter supplied";
  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  
  my $reg_if_files = $cfg->entryBool('shop', 'register_if_files', 1);

  my $user = $req->siteuser;

  if (!$user && $reg_if_files) {
    require BSE::TB::ArticleFiles;
    # scan to see if any of the products have files
    # requires a subscription or subscribes
    for my $prod (@$cart_prods) {
      my @files = BSE::TB::ArticleFiles->getBy(articleId=>$prod->{id});
      if (grep $_->{forSale}, @files) {
	return ("register before checkout", "shop/fileitems");
      }
      if ($prod->{subscription_id} != -1) {
	return ("you must be logged in to purchase a subscription", "shop/buysub");
      }
      if ($prod->{subscription_required} != -1) {
	return ("must be logged in to purchase a product requiring a subscription", "shop/subrequired");
      }
    }
  }

  my $require_logon = $cfg->entryBool('shop', 'require_logon', 0);
  if (!$user && $require_logon) {
    return ("register before checkout", "shop/logonrequired");
  }

  # check the user has the right required subs
  # and that they qualify to subscribe for limited subscription products
  if ($user) {
    for my $prod (@$cart_prods) {
      my $sub = $prod->subscription_required;
      if ($sub && !$user->subscribed_to($sub)) {
	return ("you must be subscribed to $sub->{title} to purchase one of these products", "shop/subrequired");
      }

      $sub = $prod->subscription;
      if ($sub && $prod->is_renew_sub_only) {
	unless ($user->subscribed_to_grace($sub)) {
	  return ("you must be subscribed to $sub->{title} to use this renew only product", "sub/renewsubonly");
	}
      }
      if ($sub && $prod->is_start_sub_only) {
	if ($user->subscribed_to_grace($sub)) {
	  return ("you must not be subscribed to $sub->{title} already to use this new subscription only product", "sub/newsubonly");
	}
      }
    }
  }
  
  return;
}

=item payment_types($cfg)

Returns payment type ids, and hashes describing each of the configured
payment types.

These are used to generate the tags used for testing whether payment
types are available.  Also used for validating payment type
information.

=cut

sub payment_types {
  my ($cfg) = @_;

  my @types =
    (
     {
      id => PAYMENT_CC, 
      name => 'CC', 
      desc => 'Credit Card',
      require => [ qw/cardNumber cardExpiry cardHolder/ ],
     },
     {
      id => PAYMENT_CHEQUE, 
      name => 'Cheque', 
      desc => 'Cheque',
      require => [],
     },
     {
      id => PAYMENT_CALLME,
      name => 'CallMe',
      desc => 'Call customer for payment',
      require => [],
     },
     {
      id => PAYMENT_PAYPAL,
      name => "PayPal",
      desc => "PayPal",
      require => [],
     },
    );
  my %types = map { $_->{id} => $_ } @types;

  my @payment_types = split /,/, $cfg->entry('shop', 'payment_types', '0');
  
  for my $type (@payment_types) {
    my $hash = $types{$type}; # avoid autovivification
    my $name = $cfg->entry('payment type names', $type, $hash->{name});
    my $desc = $cfg->entry('payment type descs', $type, 
			   $hash->{desc} || $name);
    my $enabled = !$cfg->entry('payment type disable', $hash->{name}, 0);
    my @require = $hash->{require} ? @{$hash->{require}} : ();
    @require = split /,/, $cfg->entry('payment type required', $type,
				      join ",", @require);
    if ($name && $desc) {
      $types{$type} = 
	{
	 id => $type,
	 name => $name, 
	 desc => $desc,
	 require => \@require,
	};
    }
  }

  for my $type (@payment_types) {
    unless ($types{$type}) {
      print STDERR "** payment type $type doesn't have a name defined\n";
      next;
    }
    $types{$type}{enabled} = 1;
  }

  # credit card payments require either encrypted emails enabled or
  # an online CC processing module
  if ($types{+PAYMENT_CC}) {
    my $noencrypt = $cfg->entryBool('shop', 'noencrypt', 0);
    my $ccprocessor = $cfg->entry('shop', 'cardprocessor');

    if ($noencrypt && !$ccprocessor) {
      $types{+PAYMENT_CC}{enabled} = 0;
      $types{+PAYMENT_CC}{message} =
	"No card processor configured and encryption disabled";
    }
  }

  # paypal requires api confguration
  if ($types{+PAYMENT_PAYPAL} && $types{+PAYMENT_PAYPAL}{enabled}) {
    require BSE::PayPal;

    unless (BSE::PayPal->configured) {
      $types{+PAYMENT_PAYPAL}{enabled} = 0;
      $types{+PAYMENT_PAYPAL}{message} = "No API configuration";
    }
  }

  return values %types;
}


1;
