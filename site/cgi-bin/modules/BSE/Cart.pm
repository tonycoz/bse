package BSE::Cart;
use strict;
use Scalar::Util;

our $VERSION = "1.000";

=head1 NAME

BSE::Cart - abstraction for the BSE cart.

=head1 SYNOPSIS

  use BSE::Cart;
  my $cart = BSE::Cart->new($req);

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
  my ($class, $req) = @_;

  my $self = bless
    {
     products => {},
     req => $req,
    }, $class;
  Scalar::Util::weaken($self->{req});
  my $items = $req->session->{cart} || [];
  my $myself = $self;
  Scalar::Util::weaken($myself);
  my $index = 0;
  $self->{items} =
    [
     map
     {
       my $myself = $self;
       my $myindex = $index++;
       my %item = %$_;
       my $id = $item{productId};
       my $options = $item{options};
       $item{product} = sub { $myself->_product($id) };
       $item{extended} = $item{price} * $item{units};
       $item{link} = sub { $myself->_product_link($id) };
       $item{option_list} = sub { $myself->_option_list($myindex) };
       $item{option_text} = sub { $myself->_option_text($myindex) };

       my $session_id = $item{session_id};
       $item{session} = sub { $myself->_item_session($session_id) };

       \%item;
     } @$items
    ];

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

=back

=head2 Item Members

=over

=item product

Returns the product for that line item.

=cut

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

=item extended

The extended price for the item.

=item link

A link to the product.

=cut

sub _product_link {
  my ($self, $id) = @_;

  my $product = $self->_product($id);
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

sub _option_list {
  my ($self, $index) = @_;

  my $item = $self->items()->[$index];
  my $product = $self->_product($item->{productId});

  return [ $product->option_descs(BSE::Cfg->single, $item->{options}) ];
}

=item option_text

Display text for options for the item.

=cut

sub _option_text {
  my ($self, $index) = @_;

  my $options = $self->_option_list($index);
  return join(", ", map "$_->{desc}: $_->{display}", @$options);
}

=item session

The session object of the seminar session

=cut

sub _item_session {
  my ($self, $id) = @_;

  $id or return;
  my $session = $self->{sessions}{$id};
  unless ($session) {
    require BSE::TB::SeminarSessions;
    $session = BSE::TB::SeminarSessions->getByPkey($id);
    $self->{sessions}{$id} = $session;
  }

  return $session;
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
