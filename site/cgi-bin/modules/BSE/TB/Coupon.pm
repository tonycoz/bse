package BSE::TB::Coupon;
use strict;
use Squirrel::Row;
our @ISA = qw/Squirrel::Row/;
use BSE::TB::CouponTiers;

our $VERSION = "1.007";

=head1 NAME

BSE::TB::Coupon - shop coupon objects

=head1 SYNOPSIS

  use BSE::TB::Coupons;

  my $coupon = BSE::TB::Coupons->make(...);

=head1 DESCRIPTION

Represents shop coupons.

=head1 METHODS

=over

=cut

sub columns {
  return qw/id code description release expiry discount_percent campaign last_modified untiered
            classid config/;
}

sub table {
  "bse_coupons";
}

sub defaults {
  require BSE::Util::SQL;
  return
    (
     last_modified => BSE::Util::SQL::now_sqldatetime(),
     untiered => 1,
     discount_percent => undef,
    );
}

=item tiers

Return the tier ids for a coupon.

This includes an entry for tier "0" if the coupon is untiered.

=cut

sub tiers {
  my ($self) = @_;

  my @tiers =
    (
     ( $self->untiered ? ( 0 ) : () ),
     BSE::TB::CouponTiers->getColumnBy
     (
      tier_id =>
      [
       coupon_id => $self->id
      ]
     )
    );

  return wantarray ? @tiers : \@tiers;
}

=item tier_objects

Return tier objects for each of the tiers this coupon is valid for.

=cut

sub tier_objects {
  my ($self) = @_;

  require BSE::TB::PriceTiers;
  return BSE::TB::PriceTiers->getSpecial(forCoupon => $self->id);
}

=item set_tiers(\@tiers)

Set the tiers for a coupon.

=cut

sub set_tiers {
  my ($self, $tiers) = @_;

  my @tiers = grep $_, @$tiers;
  $self->set_untiered((grep $_ == 0, @$tiers) ? 1 : 0);

  my %current = map { $_->tier_id => $_ }
    BSE::TB::CouponTiers->getBy2
	(
	 [
	  coupon_id => $self->id
	 ]
	);

  my %keep = map { $_->tier_id => $_ } grep $_, delete @current{@tiers};

  $_->remove for values %current;

  for my $tier_id (grep !$keep{$_}, @tiers) {
    BSE::TB::CouponTiers->make
	(
	 coupon_id => $self->id,
	 tier_id => $tier_id
	);
  }

  1;
}

sub remove {
  my ($self) = @_;

  $self->is_removable
    or return;

  my @tiers = BSE::TB::CouponTiers->getBy2
    (
     [
      coupon_id => $self->id
     ]
    );
  $_->remove for @tiers;

  $self->SUPER::remove();
}

sub json_data {
  my ($self) = @_;

  my $data = $self->data_only;
  $data->{tiers} = [ $self->tiers ];
  $data->{config_obj} = $self->config_obj;
  delete @$data{qw/config discount_percent/};

  return $data;
}

=item is_expired

Returns true if the coupon has expired.

=cut

sub is_expired {
  my ($self) = @_;

  require BSE::Util::SQL;
  return BSE::Util::SQL::now_sqldate() gt $self->expiry;
}

=item is_released

Returns true if the coupon has been released.

=cut

sub is_released {
  my ($self) = @_;

  require BSE::Util::SQL;
  return $self->release le BSE::Util::SQL::now_sqldate();
}

=item is_valid

Returns true if the coupon is both released and unexpired.

=cut

sub is_valid {
  my ($self) = @_;

  return $self->is_released && !$self->is_expired;
}

=item is_removable

Return true if the coupon can be removed.

=cut

sub is_removable {
  my ($self) = @_;

  require BSE::TB::Orders;
  return !BSE::TB::Orders->getExists([ coupon_id => $self->id ]);
}

=item is_renamable

Return true if the name can be changed.

This is currently equivalent to is_removable().

=cut

sub is_renamable {
  my ($self) = @_;

  return $self->is_removable;
}

=item is_active

Returns a list of (is active, message) for the given cart.

Wrapper around is_active() for the behaviour.

  my ($active, $msg) = $coupon->is_active($cart);

=cut

sub is_active {
  my ($self, $cart) = @_;

  return $self->behaviour->is_active($self, $cart);
}

=item discount

Return the discount in cents for the given cart.

Must only be called if is_active() returned the coupon as active.

Wrapper around discount() for the behaviour.

  my ($cents) = $coupon->discount($cart);

=cut

sub discount {
  my ($self, $cart) = @_;

  return $self->behaviour->discount($self, $cart);
}

=item product_valid

Return true if the given cart item is valid for the coupon.

Only relevant for cart-wide coupons.

=cut

sub product_valid {
  my ($self, $cart, $index) = @_;

  return $self->behaviour->product_valid($self, $cart, $index);
}

=item product_discount

Return the product specific discount per unit for the given row
(counting from zero) in the cart.

Must only be called if is_active() returned the coupon as active.

Returns zero if the coupon discount is for the cart as a whole.

Wrapper around product_discount() for the behaviour.

  my $cents = $coupon->product_discount($cart, $index);

=cut

sub product_discount {
  my ($self, $cart, $index) = @_;

  return $self->behaviour->product_discount($self, $cart, $index);
}

=item product_discount_units

Return the number of units a product specific discount applies to the given row
(counting from zero) in the cart.

Must only be called if is_active() returned the coupon as active.

Returns zero if the coupon discount is for the cart as a whole.

Wrapper around product_discount_units() for the behaviour.

  my $cents = $coupon->product_discount_units($cart, $index);

=cut

sub product_discount_units {
  my ($self, $cart, $index) = @_;

  return $self->behaviour->product_discount_units($self, $cart, $index);
}

=item describe

Describe the behaviour of the coupon briefly.

=cut

sub describe {
  my ($self) = @_;

  $self->behaviour->describe;
}

=item cart_wide($cart)

Returns true if the discount provided by the behaviour applies to the
cart as a whole.

=cut

sub cart_wide {
  my ($self, $cart) = @_;

  return $self->behaviour->cart_wide($cart);
}

=item set_code($code)

Set the coupon code.  Requires that is_renamable() be true.

=cut

sub set_code {
  my ($self, $code) = @_;

  $self->is_renamable
    or return;

  $self->{code} = $code;
}

sub fields {
  my ($self) = @_;

  my $bclasses = BSE::TB::Coupons->behaviour_classes;

  my %fields =
    (
     code =>
     {
      description => "Coupon Code",
      required => 1,
      width => 20,
      maxlength => 40,
      htmltype => "text",
      rules => "dh_one_line;coupon_code",
     },
     description =>
     {
      description => "Description",
      required => 1,
      width => 80,
      htmltype => "text",
      rules => "dh_one_line",
     },
     release =>
     {
      description => "Release Date",
      required => 1,
      width => 10,
      htmltype => "text",
      type => "date",
      rules => "date",
     },
     expiry =>
     {
      description => "Expiry Date",
      required => 1,
      width => 10,
      htmltype => "text",
      type => "date",
      rules => "date",
     },
     campaign =>
     {
      description => "Campaign",
      width => 20,
      maxlength => 20,
      htmltype => "text",
      rules => "dh_one_line",
     },
     tiers =>
     {
      description => "Price Tiers",
      htmltype => "multicheck",
      select =>
      {
       values => sub {
	 require BSE::TB::PriceTiers;
	 return
	   [
	    { id => 0, description => "Untiered" },
	    BSE::TB::PriceTiers->getColumnsBy
	    (
	     [ qw(id description) ],
	     [ ],
	     { order => "display_order asc" },
	    ),
	   ];
       },
       id => "id",
       label => "description",
      },
     },
     classid =>
     {
      description => "Coupon Class",
      htmltype => "select",
      select =>
      {
       id => "id",
       label => "label",
       values =>
       [
	sort { lc $a->{label} cmp lc $b->{label} }
	map
	+{
	  id => $_,
	  label => $bclasses->{$_}->class_description,
	 },
	sort { lc $bclasses->{$a}->class_description cmp lc $bclasses->{$b}->class_description}
	keys %$bclasses
       ],
      },
     },
    );

  if (ref $self && !$self->is_renamable) {
    $fields{code}{readonly} = 1;
  }

  require BSE::Validate;
  return BSE::Validate::bse_configure_fields(\%fields, BSE::Cfg->single, "bse coupon validation");
}

sub rules {
  return
    {
     coupon_code =>
     {
      match => qr/\A[a-zA-Z0-9]+\z/,
      error => '$n can only contain letters and digits',
     },
    };
}

sub config_obj {
  my ($self) = @_;

  my $config = $self->config;
  $config = "{}" if $config eq "";

  require JSON;
  my $obj = JSON->new->decode($config);
  $obj->{discount_percent} = $self->discount_percent;

  return $obj;
}

sub set_config_obj {
  my ($self, $obj) = @_;

  $self->set_discount_percent(delete $obj->{discount_percent});

  require JSON;
  $self->set_config(JSON->new->encode($obj));
}

sub behaviour {
  my ($self) = @_;

  delete $self->{_behaviour}
    if $self->{_classid} ne $self->classid
    || $self->{_config} ne $self->config;

  $self->{_behaviour} ||=
    BSE::TB::Coupons->behaviour_class($self->classid)->new($self->config_obj);
  $self->{_classid} = $self->classid;
  $self->{_config} = $self->config;

  $self->{_behaviour};
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
