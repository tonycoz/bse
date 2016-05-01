package BSE::Coupon::ProductPercent;
use parent 'BSE::Coupon::Base';
use strict;

our $VERSION = "1.000";

sub config_fields {
  my ($class) = @_;

  require BSE::TB::Products;

  return
    {
     discount_percent =>
     {
      description => "Discount",
      required => 1,
      width => 5,
      htmltype => "text",
      rules => "coupon_percent",
      units => "%",
      order => 1,
     },
     product_id =>
     {
      description => "Product",
      required => 1,
      htmltype => "select",
      order => 2,
      select =>
      {
       id => "id",
       label => "label",
       values =>
       [
	sort { lc $a->{label} cmp lc $b->{label} }
	map
	+{
	  id => $_->id,
	  label => $_->title,
	 }, BSE::TB::Products->all
       ],
      },
     },
     max_units =>
     {
      description => "Max Units",
      required => 1,
      width => 5,
      htmltype => "text",
      rules => "natural",
      units => "units",
      order => 3,
     },
    };
}

sub config_rules {
  return
    (
    );
}

sub config_valid {
  my ($self, $config, $errors) = @_;

  require BSE::TB::Products;
  my ($prod) = BSE::TB::Products->getByPkey($config->{product_id});
  unless ($prod) {
    $errors->{product_id} = "Unknown product id";
  }
  !keys %$errors;
}

sub class_description {
  "Simple product specific discount";
}

sub _product {
  my ($self) = @_;

  unless ($self->{_product}) {
    require BSE::TB::Products;
    $self->{_product} = BSE::TB::Products->getByPkey($self->{config}{product_id});
  }

  $self->{_product};
}

sub is_active {
  my ($self, $coupon, $cart) = @_;

  for my $item ($cart->items) {
    return 1
      if $item->product->id == $self->{config}{product_id};
  }

  require BSE::TB::Products;
  my ($prod) = $self->_product;

  return ( 0, "This coupon only applies to ".$prod->title );
}

sub cart_wide {
  0;
}

sub _row_discounts {
  my ($self, $coupon, $cart) = @_;

  my $max_units = $self->{config}{max_units};
  my $product_id = $self->{config}{product_id};
  my $discount = $self->{config}{discount_percent};
  my $units_seen = 0;
  my @row_discounts;
  for my $item ($cart->items) {
    my $discount_units = 0;
    my $row_discount = 0;
    if ($item->product_id == $product_id) {
      my $prod_discount = int($item->price * $discount / 100);
      if ($max_units) {
	if ($units_seen < $max_units) {
	  $row_discount = $prod_discount;
	  my $units_left = $max_units - $units_seen;
	  $discount_units = $units_left > $item->units ? $item->units : $units_left;
	}
      }
      else {
	$row_discount = $prod_discount;
	$discount_units = $item->units;
      }
      $units_seen += $item->units;
    }
    push @row_discounts, [ $row_discount, $discount_units ];
  }

  @row_discounts;
}

sub discount {
  my ($self, $coupon, $cart) = @_;

  my @discounts = $self->_row_discounts($coupon, $cart);

  my $total_discount = 0;
  for my $row (@discounts) {
    $total_discount += $row->[0] * $row->[1];
  }

  return $total_discount;
}

sub product_discount {
  my ($self, $coupon, $cart, $index) = @_;

  my @discounts = $self->_row_discounts($coupon, $cart);

  return $discounts[$index][0];
}

sub product_discount_units {
  my ($self, $coupon, $cart, $index) = @_;

  my @discounts = $self->_row_discounts($coupon, $cart);

  return $discounts[$index][1];
}

sub describe {
  my ($self) = @_;

  my $desc = sprintf("%.1f%% discount on ", $self->{config}{discount_percent});
  if ($self->{config}{max_units}) {
    $desc .= "the first $self->{config}{max_units} units of ";
  }
  $desc .= $self->_product->title;

  $desc;
}

1;
