package BSE::Shop::Util;
use strict;
use vars qw(@ISA @EXPORT_OK);
@ISA = qw/Exporter/;
@EXPORT_OK = qw/shop_cart_tags cart_item_opts nice_options shop_nice_options
                total shop_total load_order_fields basic_tags need_logon
                get_siteuser payment_types/;
use Constants qw/:shop/;
use BSE::Util::SQL qw(now_sqldate);
use BSE::Util::Tags;
use BSE::CfgInfo qw(custom_class);
use Carp 'confess';
use DevHelp::HTML qw(escape_html);

# returns a list of tags which display the cart details
sub shop_cart_tags {
  my ($acts, $cart, $cart_prods, $session, $q, $cfg, $stage) = @_;

  $cfg or confess "No config";
  $cfg->isa("BSE::Cfg") or confess "Not a config";

  my $item_index;
  my $option_index;
  my @options;
  my $user;
  if ($session->{userid}) {
    require 'SiteUsers.pm';
    $user = SiteUsers->getBy(userId=>$session->{userid});
  }
  my $sem_session;
  my $location;
  my $item;
  my $product;
  return
    (
     BSE::Util::Tags->basic($acts, $q, $cfg),
     ifUser => sub { $user },
     user => sub { CGI::escapeHTML($user ? $user->{$_[0]} : '') },
     iterate_items_reset => sub { $item_index = -1 },
     iterate_items => 
     sub { 
       if (++$item_index < @$cart) {
	 $option_index = -1;
	 @options = cart_item_opts($cart->[$item_index], 
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
       $value;
     },
     extended =>
     sub { 
       my $what = $_[0] || 'retailPrice';
       $cart->[$item_index]{units} * $cart_prods->[$item_index]{$what};
     },
     index => sub { $item_index },
     total => 
     sub { total($cart, $cart_prods, $session->{custom}, $cfg, $stage) },
     count => sub { scalar @$cart },
     iterate_options_reset => sub { $option_index = -1 },
     iterate_options => sub { ++$option_index < @options },
     option => sub { CGI::escapeHTML($options[$option_index]{$_[0]}) },
     ifOptions => sub { @options },
     options => sub { nice_options(@options) },
     session => [ \&tag_session, \$item, \$sem_session ],
     location => [ \&tag_location, \$item, \$location ],
     custom_class($cfg)
     ->checkout_actions($acts, $cart, $cart_prods, $session->{custom}, $q, $cfg),
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
  my ($wantcard, $q, $order, $session, $cart_prods, $error) = @_;

  require 'BSE/Cfg.pm';
  my $cfg = BSE::Cfg->new;

  my $cust_class = custom_class($cfg);

  my @required = $cust_class->required_fields($CGI::Q, $session->{custom});
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

  if (need_logon($cfg, \@cart, \@products, $session, $q)) {
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
  my ($cfg, $cart, $cart_prods, $session, $cgi) = @_;

  defined $cgi or confess "No cgi parameter supplied";
  
  my $reg_if_files = $cfg->entryBool('shop', 'register_if_files', 1);

  my $user = get_siteuser($session, $cfg, $cgi);

  if (!$user && $reg_if_files) {
    require ArticleFiles;
    # scan to see if any of the products have files
    # requires a subscription or subscribes
    for my $prod (@$cart_prods) {
      my @files = ArticleFiles->getBy(articleId=>$prod->{id});
      if (grep $_->{forSale}, @files) {
	return ("register before checkout", "shop/fileitems");
      }
      if ($prod->{subscription_id} != -1) {
	return ("you must be logged in to purchase a subscription", "shop/buysub");
      }
      if ($prod->{subscription_required} != -1) {
	return ("must be logged in to purchse a product requiring a subscription", "shop/subrequired");
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

sub get_siteuser {
  my ($session, $cfg, $cgi) = @_;

  require SiteUsers;
  if ($cfg->entryBool('custom', 'user_auth')) {
    my $custom = custom_class($cfg);
    
    return $custom->siteuser_auth($session, $cgi, $cfg);
  }
  else {
    my $userid = $session->{userid}
      or return;
    my $user = SiteUsers->getBy(userId=>$userid)
      or return;
    $user->{disabled}
      and return;
    
    return $user;
  }
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

  my %types =
    (
     0 => { 
	   id => 0, 
	   name => 'CC', 
	   desc => 'Credit Card',
	   require => [ qw/cardNumber cardExpiry cardHolder/ ],
	  },
     1 => { 
	   id => 1, 
	   name => 'Cheque', 
	   desc => 'Cheque',
	   require => [],
	  },
     2 => {
	   id => 2,
	   name => 'CallMe',
	   desc => 'Call customer for payment',
	   require => [],
	  },
    );

  my @payment_types = split /,/, $cfg->entry('shop', 'payment_types', '0');
  
  for my $type (@payment_types) {
    my $hash = $types{$type}; # avoid autovivification
    my $name = $cfg->entry('payment type names', $type, $hash->{name});
    my $desc = $cfg->entry('payment type descs', $type, 
			   $hash->{desc} || $name);
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
  if ($types{0}) {
    my $noencrypt = $cfg->entryBool('shop', 'noencrypt', 0);
    my $ccprocessor = $cfg->entry('shop', 'cardprocessor');

    if ($noencrypt && !$ccprocessor) {
      $types{0}{enabled} = 0;
    }
  }

  return values %types;
}


1;
