package BSE::Custom;
use BSE::CustomBase;
use strict;

use vars qw(@ISA);
@ISA = qw(BSE::CustomBase);

# these values are all in cents
# flagfall, per item and minimum for overseas deliveries
my $FREIGHT_OS_FLAG = 500;
my $FREIGHT_OS_PER = 450;
my $FREIGHT_OS_MIN = 0;

# flagfall, per item and minimum for australian deliveries
my $FREIGHT_AUST_FLAG = 300;
my $FREIGHT_AUST_PER = 100;
my $FREIGHT_AUST_MIN = 0;

# 
my $FREIGHT_AUST_PASS = 100;
my $FREIGHT_OS_PASS = 100;

sub _is_fringe_pass {
  my ($product) = @_;

  $product->{title} =~ /fringepass/i;
}

sub _have_fringe_pass {
  my ($products) = @_;

  scalar(grep _is_fringe_pass($_), @$products);
}

sub _only_fringe_pass {
  my ($products) = @_;

  !grep !_is_fringe_pass($_), @$products;
}

sub _freight {
  my ($items, $products, $overseas) = @_;

  return 0 unless @$items;
  if (!_only_fringe_pass($products)) {
    my $total = $overseas ? $FREIGHT_OS_FLAG : $FREIGHT_AUST_FLAG;
    my $per = $overseas ? $FREIGHT_OS_PER : $FREIGHT_AUST_PER;
    my $min = $overseas ? $FREIGHT_OS_MIN : $FREIGHT_AUST_MIN;
    my $pass = 0;
    for my $index (0..$#{$items}) {
      if (_is_fringe_pass($products->[$index])) {
	# assume this is absorbed
	#$pass = $overseas ? $FREIGHT_OS_PASS : $FREIGHT_AUST_PASS
      }
      else {
	$total += $items->[$index]{units} * $per;
      }
    }
    $total += $pass;
    if ($total < $min) {
      $total = $min;
    }

    return $total;
  }
  else {
    # only fringe passes
    return $overseas ? $FREIGHT_OS_PASS : $FREIGHT_AUST_PASS;
  }
}

sub checkout_actions {
  my ($class, $acts, $items, $products, $state) = @_;

  my $want_password = _have_fringe_pass($products);

  return
    (
     ifFringePass => sub { $want_password },
     freight => sub { _freight($items, $products, $state->{overseas}) },
     freight_aust => sub { _freight($items, $products, 0) },
     freight_overseas => sub { _freight($items, $products, 1) },
     ifOverseas => sub { $state->{overseas} },
    );
}

sub order_save {
  my ($class, $cgi, $order, $items, $products, $state) = @_;

  if (_have_fringe_pass($products)) {
    # the user should have entered as password into the "fringepassword"
    # field
    my $password = $cgi->param('fringepassword');
    my $confirm = $cgi->param('fringepassconfirm');
    unless (defined $password && $password ne '') {
      die "Please enter a password to be used with your Fringe Pass\n";
    }
    # we only check for confirmation if there was a confirm field
    # on the form
    if (defined($confirm) && $confirm ne $password) {
      die "Your Fringe Pass password does not match the Confirm field\n";
    }

    use Digest::MD5 qw(md5_hex);
    $order->{billFirstName} = md5_hex($password.$order->{randomId});
  }
  $state->{overseas} = $cgi->param('overseas');
  if (!$state->{overseas} && $order->{delivCountry} !~ /^\s*$/i) {
    die "Please only enter a country if you are overseas\n";
  }
  if ($state->{overseas} && $order->{delivCountry} =~ /^\s*$/i) {
    die "Please enter a country if you are overseas\n";
  }
}

sub total_extras {
  my ($class, $items, $products, $state) = @_;

  _freight($items, $products, $state->{overseas});
}

sub recalc {
  my ($class, $q, $item, $products, $state) = @_;

  $state->{overseas} = $q->param('overseas');
}

sub cart_actions {
  my ($class, $acts, $items, $products, $state) = @_;

  return
    (
     freight => sub { _freight($items, $products, $state->{overseas}) },
     freight_aust => sub { _freight($items, $products, 0) },
     freight_overseas => sub { _freight($items, $products, 1) },
     ifOverseas => sub { $state->{overseas} },
    );
}

sub required_fields {
  my ($class, $q, $state) = @_;

  grep $_ ne 'country', $class->SUPER::required_fields($q, $state);
}

sub purchase_actions {
  my ($class, $acts, $items, $products, $state) = @_;

  return
    (
     freight => sub { _freight($items, $products, $state->{overseas}) },
    );
}

1;

=head1 NAME

  BSE::Custom - contains methods you implement to customize the
  behaviour of BSE.

=head1 DESCRIPTION

  See L<BSE::CustomBase> for a list of the methods you can customize.

=cut

