package BSE::Cart;
use strict;
use Scalar::Util;

our $VERSION = "1.002";

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

  my $self = bless
    {
     products => {},
     req => $req,
     stage => $stage,
    }, $class;
  Scalar::Util::weaken($self->{req});
  my $items = $req->session->{cart} || [];
  my $myself = $self;
  Scalar::Util::weaken($myself);
  my $index = 0;
  $self->{items} =  [ map BSE::Cart::Item->new($_, $index++, $self), @$items ];

  return $self;
}

=item items()

Return an array reference of cart items.

=cut

sub items {
  return $_[0]{items};
}

=item products().

Return an array reference of products in the cart, corresponding to
the array reference returned by items().

=cut

sub products {
  my $self = shift;
  return [ map $self->_product($_->{productId}), @{$self->items} ];
}

=item total_cost

Return the total cost of the items in the cart.

=cut

sub total_cost {
  my ($self) = @_;

  my $total_cost = 0;
  for my $item (@{$self->items}) {
    $total_cost += $item->{extended};
  }

  return $total_cost;
}

=item total_units

Return the total number of units in the cart.

=cut

sub total_units {
  my ($self) = @_;

  my $total_units = 0;
  for my $item (@{$self->items}) {
    $total_units += $item->{units};
  }

  return $total_units;
}

=item total

Total of items in the cart and any custom extras.

=cut

sub total {
  my ($self) = @_;

  "FIXME";
}

sub _product {
  my ($self, $id) = @_;

  my $product = $self->{products}{$id};
  unless ($product) {
    require Products;
    $product = Products->getByPkey($id)
      or die "No product $id\n";
    # FIXME
    if ($product->generator ne "Generate::Product") {
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

  return self->$base() * $self->{units};
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

  return [ $self->product->option_descs(BSE::Cfg->single, $self->{options}) ];
}

=item option_text

Display text for options for the item.

=cut

sub option_text {
  my ($self, $index) = @_;

  my $options = $self->option_list;
  return join(", ", map "$_->{desc}: $_->{display}", @$options);
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

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
