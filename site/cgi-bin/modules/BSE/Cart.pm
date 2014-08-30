package BSE::Cart;
use strict;
use Scalar::Util;

our $VERSION = "1.008";

=head1 NAME

BSE::Cart - abstraction for the BSE cart.

=head1 SYNOPSIS

  use BSE::Cart;
  my $cart = BSE::Cart->new($req, $stage);

  my $items = $cart->items;
  my $products = $cart->products;

=head1 DESCRIPTION

This class provides a simple abstraction for access to the BSE
shopping cart.

This is intended for use in templates, but may be expanded further.

=head1 METHODS

=over

=item new()

Create a new cart object based on the session.

=cut

sub new {
  my ($class, $req, $stage) = @_;

  $stage ||= "";

  my $self = bless
    {
     products => {},
     req => $req,
     stage => $stage,
     shipping => 0,
    }, $class;
  Scalar::Util::weaken($self->{req});
  my $items = $req->session->{cart} || [];
  my $myself = $self;
  Scalar::Util::weaken($myself);
  my $index = 0;
  $self->{items} =  [ map BSE::Cart::Item->new($_, $index++, $self), @$items ];

  if ($stage eq 'cart' || $stage eq 'checkout') {
    $self->_enter_cart;
  }
  elsif ($stage eq 'checkupdate') {
    $self->_checkout_update;
  }

  $self->{coupon_code} = $self->{req}->session->{cart_coupon_code};
  defined $self->{coupon_code} or $self->{coupon_code} = "";

  return $self;
}

sub _enter_cart {
  my ($self) = @_;

  my $req = $self->{req};
  require BSE::CfgInfo;

  $req->session->{custom} ||= {};
  my %custom_state = %{$req->session->{custom}};

  $self->{custom_state} = \%custom_state;

  my $cust_class = BSE::CfgInfo::custom_class($self->{req}->cfg);
  $cust_class->enter_cart(scalar $self->items, scalar $self->products,
			  \%custom_state, $req->cfg);
}

sub _checkout_update {
  my ($self) = @_;

  my $req = $self->{req};
  require BSE::CfgInfo;

  $req->session->{custom} ||= {};
  my %custom_state = %{$req->session->{custom}};

  $self->{custom_state} = \%custom_state;

  my $cust_class = BSE::CfgInfo::custom_class($self->{req}->cfg);
  $cust_class->checkout_update
    ($req->cgi, scalar $self->items, scalar $self->products,
     \%custom_state, $req->cfg);
}

=item is_empty()

Return true if the cart has no items in it.

=cut

sub is_empty {
  my ($self) = @_;

  return @{$self->{items}} == 0;
}

=item items()

Return an array reference of cart items.

=cut

sub items {
  return wantarray ? @{$_[0]{items}} : $_[0]{items};
}

=item products().

Return an array reference of products in the cart, corresponding to
the array reference returned by items().

=cut

sub products {
  my $self = shift;

  my @products = map $self->_product($_->{productId}), @{$self->items};

  return wantarray ? @products : \@products;
}

=item total_cost

Return the total cost of the items in the cart.

This does not include shipping costs and is not discounted.

=cut

sub total_cost {
  my ($self) = @_;

  my $total_cost = 0;
  for my $item (@{$self->items}) {
    $total_cost += $item->extended_retailPrice;
  }

  return $total_cost;
}

=item gst

Return the total GST paid for the items in the cart.

This currently depends on the gst values of the products.

This ignores the coupon code discount.

=cut

sub gst {
  my ($self) = @_;

  my $total_gst = 0;
  for my $item (@{$self->items}) {
    $total_gst += $item->extended_gst;
  }

  return $total_gst;
}

=item wholesaleTotal

Return the wholesale cost for the items in the cart.

This depends on the wholesale values of the products.

=cut

sub wholesaleTotal {
  my ($self) = @_;

  my $total_wholesale = 0;
  for my $item (@{$self->items}) {
    $total_wholesale += $item->extended_wholesale;
  }

  return $total_wholesale;
}

=item discounted_product_cost

Cost of products with an product discount taken into account.

Note: this rounds the total B<down>.

=cut

sub discounted_product_cost {
  my ($self) = @_;

  my $cost = $self->total_cost;

  if ($self->coupon_active) {
    $cost -= $cost * $self->coupon_code_discount_pc / 100;
  }

  return int($cost);
}

=item product_cost_discount

Return any amount taken off the product cost.

=cut

sub product_cost_discount {
  my ($self) = @_;

  return $self->total_cost - $self->discounted_product_cost;
}

=item cfg_shipping

Return true if the system is configured to prompt for shipper
information.

=cut

sub cfg_shipping {
  my $self = shift;

  return $self->{req}->cfg->entry("shop", "shipping", 0);
}

=item set_shipping_cost()

Set the cost of shipping.

Called by the shop.

=cut

sub set_shipping_cost {
  my ($self, $cost) = @_;

  $self->{shipping} = $cost;
}

=item shipping_cost()

Fetch the cost of shipping.

=cut

sub shipping_cost {
  my ($self) = @_;

  return $self->{shipping};
}

=item set_shipping_method

Set the stored shipping method.  For internal use.

=cut

sub set_shipping_method {
  my ($self, $method) = @_;

  $self->{shipping_method} = $method;
}

=item shipping_method

The description of the selected shipping method.

=cut

sub shipping_method {
  my ($self) = @_;

  return $self->{shipping_method};
}

=item set_shipping_name

Set the stored shipping name.  For internal use.

=cut

sub set_shipping_name {
  my ($self, $name) = @_;

  $self->{shipping_name} = $name;
}

=item shipping_name

The name of the selected shipping method.

=cut

sub shipping_name {
  my ($self) = @_;

  return $self->{shipping_name};
}

=item set_delivery_in

Set the stored delivery time in days.

=cut

sub set_delivery_in {
  my ($self, $days) = @_;

  $self->{delivery_in} = $days;
}

=item delivery_in

The expected delivery time in days.  Some shippers may not supply
this, in which case this will be an undefined value.

=cut

sub delivery_in {
  my ($self) = @_;

  return $self->{delivery_in};
}

=item total_units

Return the total number of units in the cart.

=cut

sub total_units {
  my ($self) = @_;

  my $total_units = 0;
  for my $item (@{$self->items}) {
    $total_units += $item->units;
  }

  return $total_units;
}

=item total

Total of items in the cart, any custom costs and shipping costs.

=cut

sub total {
  my ($self) = @_;

  my $cost = 0;

  $cost += $self->discounted_product_cost;

  $cost += $self->shipping_cost;

  $cost += $self->custom_cost;

  return $cost;
}

=item coupon_code

The current coupon code.

=cut

sub coupon_code {
  my ($self) = @_;

  return $self->{coupon_code};
}

=item set_coupon_code()

Used by the shop to set the coupon code.

=cut

sub set_coupon_code {
  my ($self, $code) = @_;

  $code =~ s/\A\s+//;
  $code =~ s/\s+\z//;
  $self->{coupon_code} = $code;
  delete $self->{coupon_valid};
  $self->{req}->session->{cart_coupon_code} = $code;
}

=item coupon_code_discount_pc

The percentage discount for the current coupon code, if that code is
valid and the contents of the cart are valid for that coupon code.

=cut

sub coupon_code_discount_pc {
  my ($self) = @_;

  $self->coupon_valid
    or return 0;

  return $self->{coupon_check}{coupon}->discount_percent;
}

=item coupon_valid

Return true if the current coupon code is valid

=cut

sub coupon_valid {
  my ($self) = @_;

  unless ($self->{coupon_check}) {
    if (length $self->{coupon_code}) {
      require BSE::TB::Coupons;
      my ($coupon) = BSE::TB::Coupons->getBy(code => $self->{coupon_code});
      my %check =
	(
	 coupon => $coupon,
	 valid => 0,
	);
      #print STDERR " coupon $coupon\n";
      #print STDERR "released ", 0+ $coupon->is_released, " expired ",
      #	0+$coupon->is_expired, " valid ", 0+$coupon->is_valid, "\n" if $coupon;
      if ($coupon && $coupon->is_valid) {
	$check{valid} = 1;
	$check{active} = 1;
	my %tiers = map { $_ => 1 } $coupon->tiers;
      ITEM:
	for my $item ($self->items) {
	  my $applies = 1;
	  if ($item->tier_id) {
	    #print STDERR "tier ", $item->tier_id, " tiers ", join(",", keys %tiers), "\n";
	    if (!$tiers{$item->tier_id}) {
	      $applies = 0;
	    }
	  }
	  else {
	    if (!$coupon->untiered) {
	      $applies = 0;
	    }
	  }
	  $item->{coupon_applies} = $applies;
	  $applies or $check{active} = 0;
	}
      }
      $self->{coupon_check} = \%check;
    }
    else {
      $self->{coupon_check} =
	{
	 valid => 0,
	 active => 0,
	};
    }
  }

  return $self->{coupon_check}{valid};
}

=item coupon_active

Return true if the current coupon is active, ie. both valid and the
cart has products of all the right tiers.

=cut

sub coupon_active {
  my ($self) = @_;

  $self->coupon_valid
    or return 0;

  return $self->{coupon_check}{active};
}

=item coupon

The current coupon object, if and only if the coupon code is valid.

=cut

sub coupon {
  my ($self) = @_;

  $self->coupon_valid
    or return;

  $self->{coupon_check}{coupon};
}

=item custom_cost

Return any custom cost specified by a custom class.

=cut

sub custom_cost {
  my ($self) = @_;

  unless (exists $self->{custom_cost}) {
    my $obj = BSE::CfgInfo::custom_class($self->{req}->cfg);
    $self->{custom_cost} =
      $obj->total_extras(scalar $self->items, scalar $self->products,
			 $self->{custom_state}, $self->{req}->cfg, $self->{stage});
  }

  return $self->{custom_cost};
}

=item have_sales_files

Return true if the cart contains products with files that are for
sale.

=cut

sub have_sales_files {
  my ($self) = @_;

  unless (defined $self->{have_sales_files}) {
    $self->{have_sales_files} = 0;
  PRODUCTS:
    for my $prod (@{$self->products}) {
      if ($prod->has_sales_files) {
	$self->{have_sales_files} = 1;
	last PRODUCTS;
      }
    }
  }

  return $self->{have_sales_files};
}

=item need_logon

Return true if the cart contains items that the user needs to be
logged on to purchase, or if the current user isn't qualified to
purchase the item.

Call need_logon_message() to get the reason for this method returning
false.

=cut

sub need_logon {
  my ($self) = @_;

  unless (exists $self->{need_logon}) {
    $self->{need_logon} = $self->_need_logon;
  }

  $self->{need_logon} or return;

  return 1;
}

=item need_logon_message

Returns a list with the error message and message id of the reason the
user needs to logon for this cart.

=cut

sub need_logon_message {
  my ($self) = @_;

  unless (exists $self->{need_logon}) {
    $self->{need_logon} = $self->_need_logon;
  }

  return @{$self->{logon_reason}};
}

=item custom_state

State managed by a custom class.

=cut

sub custom_state {
  my ($self) = @_;

  $self->{custom_state};
}

=item affiliate_code

Return the stored affiliate code.

=cut

sub affiliate_code {
  my ($self) = @_;

  my $code = $self->{req}->session->{affiliate_code};
  defined $code or $code = '';

  return $code;
}

=item any_phyiscal_products

Returns true if the cart contains any physical products, ie. needs
shipping.

=cut

sub any_physical_products {
  my ($self) = @_;

  for my $prod (@{$self->products}) {
    if ($prod->weight) {
      return 1;
      last;
    }
  }

  return 0;
}


=item _need_logon

Internal implementation of need_logon.

=cut

sub _need_logon {
  my ($self) = @_;

  my $cfg = $self->{req}->cfg;

  $self->{logon_reason} = [];

  my $reg_if_files = $cfg->entryBool('shop', 'register_if_files', 1);

  my $user = $self->{req}->siteuser;

  if (!$user && $reg_if_files) {
    require BSE::TB::ArticleFiles;
    # scan to see if any of the products have files
    # requires a subscription or subscribes
    for my $prod (@{$self->products}) {
      my @files = $prod->files;
      if (grep $_->forSale, @files) {
	$self->{logon_reason} =
	  [ "register before checkout", "shop/fileitems" ];
	return;
      }
      if ($prod->{subscription_id} != -1) {
	$self->{logon_reason} =
	  [ "you must be logged in to purchase a subscription", "shop/buysub" ];
	return;
      }
      if ($prod->{subscription_required} != -1) {
	$self->{logon_reason} = 
	  [ "must be logged in to purchase a product requiring a subscription", "shop/subrequired" ];
	return;
      }
    }
  }

  my $require_logon = $cfg->entryBool('shop', 'require_logon', 0);
  if (!$user && $require_logon) {
    $self->{logon_reason} =
      [ "register before checkout", "shop/logonrequired" ];
    return;
  }

  # check the user has the right required subs
  # and that they qualify to subscribe for limited subscription products
  if ($user) {
    for my $prod (@{$self->products}) {
      my $sub = $prod->subscription_required;
      if ($sub && !$user->subscribed_to($sub)) {
	$self->{logon_reason} =
	  [ "you must be subscribed to $sub->{title} to purchase one of these products", "shop/subrequired" ];
	return;
      }

      $sub = $prod->subscription;
      if ($sub && $prod->is_renew_sub_only) {
	unless ($user->subscribed_to_grace($sub)) {
	  $self->{logon_reason} =
	    [ "you must be subscribed to $sub->{title} to use this renew only product", "sub/renewsubonly" ];
	  return;
	}
      }
      if ($sub && $prod->is_start_sub_only) {
	if ($user->subscribed_to_grace($sub)) {
	  $self->{logon_reason} =
	    [ "you must not be subscribed to $sub->{title} already to use this new subscription only product", "sub/newsubonly" ];
	  return;
	}
      }
    }
  }
  
  return;
}

sub _product {
  my ($self, $id) = @_;

  my $product = $self->{products}{$id};
  unless ($product) {
    require Products;
    $product = Products->getByPkey($id)
      or die "No product $id\n";
    # FIXME
    if ($product->generator ne "BSE::Generate::Product") {
      require BSE::TB::Seminars;
      $product = BSE::TB::Seminars->getByPkey($id)
	or die "Not a product, not a seminar $id\n";
    }

    $self->{products}{$id} = $product;
  }
  return $product;
}

sub _session {
  my ($self, $id) = @_;
  my $session = $self->{sessions}{$id};
  unless ($session) {
    require BSE::TB::SeminarSessions;
    $session = BSE::TB::SeminarSessions->getByPkey($id);
    $self->{sessions}{$id} = $session;
  }

  return $session;
}

=item cleanup()

Clean up the cart, removing any items that are unreleased, expired or
unlisted.

For BSE use.

=cut

sub cleanup {
  my ($self) = @_;

  my @newitems;
  for my $item ($self->items) {
    my $product = $item->product;

    if ($product->is_released && !$product->is_expired && $product->listed) {
      push @newitems, $item;
    }
  }

  $self->{items} = \@newitems;
}

=item empty

Empty the cart.

=cut

sub empty {
  my ($self) = @_;

  my $req = $self->{req};

  # empty the cart ready for the next order
  delete @{$req->session}{qw/order_info order_info_confirmed order_need_delivery cart order_work cart_coupon_code/};
}

=back

=cut

package BSE::Cart::Item;

sub new {
  my ($class, $raw_item, $index, $cart) = @_;

  my $item = bless
    {
     %$raw_item,
     index => $index,
     cart => $cart,
    }, $class;

  Scalar::Util::weaken($item->{cart});

  return $item;
}

=head2 Item Members

=over

=item product

Returns the product for that line item.

=cut

sub product {
  my $self = shift;

  return $self->{cart}->_product($self->{productId});
}

=item price

=cut

sub price {
  my ($self) = @_;

  unless (defined $self->{calc_price}) {
    $self->{calc_price} = $self->product->price(user => $self->{cart}{req}->siteuser);
  }

  return $self->{calc_price};
}

=item extended

The extended price for the item.

=cut

sub extended {
  my ($self, $base) = @_;

  $base =~ /^(price|retailPrice|gst|wholesalePrice)$/
    or return 0;

  return $self->$base() * $self->{units};
}

sub extended_retailPrice {
  $_[0]->extended("price");
}

sub extended_wholesalePrice {
  $_[0]->extended("wholesalePrice");
}

sub extended_gst {
  $_[0]->extended("gst");
}

=item units

The number of units.

=cut

sub units {
  $_[0]{units};
}

=item session_id

The seminar session id, if any.

=cut

sub session_id {
  $_[0]{session_id};
}

=item tier_id

The pricing tier id.

=cut

sub tier_id {
  $_[0]{tier};
}

=item link

A link to the product.

=cut

sub link {
  my ($self, $id) = @_;

  my $product = $self->product;
  my $link = $product->link;
  unless ($link =~ /^\w+:/) {
    $link = BSE::Cfg->single->entryErr("site", "url") . $link;
  }

  return $link;
}

=item option_list

Return a list of options for the item, each with:

=over

=item *

id, name - the identifier for the option

=item *

value - the value of the option.

=item *

desc - the description of the option

=item *

display - display of the option value

=back

=cut

sub option_list {
  my ($self, $index) = @_;

  my @options = $self->product->option_descs(BSE::Cfg->single, $self->{options});

  return wantarray ? @options : \@options;
}

=item option_text

Display text for options for the item.

=cut

sub option_text {
  my ($self, $index) = @_;

  my $options = $self->option_list;
  return join(", ", map "$_->{desc}: $_->{display}", @$options);
}

=item coupon_applies

Returns true if the current coupon code applies to the item.

=cut

sub coupon_applies {
  my ($self) = @_;

  $self->{cart}->coupon_valid
    or return 0;

  return $self->{coupon_applies};
}

=item session

The session object of the seminar session

=cut

sub session {
  my ($self) = @_;

  $self->{session_id} or return;
  return $self->{cart}->_session($self->{session_id});
}


my %product_keys;

sub AUTOLOAD {
  our $AUTOLOAD;
  (my $name = $AUTOLOAD) =~ s/^.*:://;
  unless (%product_keys) {
    require Products;
    %product_keys = map { $_ => 1 } Product->columns;
  }

  if ($product_keys{$name}) {
    return $_[0]->product->$name();
  }
  else {
    return "* unknown method $name *";
  }
}

=item description

=item title

=cut

sub description {
  my ($self) = @_;

  $self->product->description;
}

sub title {
  my ($self) = @_;

  $self->product->title;
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
