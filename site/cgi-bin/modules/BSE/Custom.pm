package BSE::Custom;
use BSE::CustomBase;

use vars qw(@ISA);
@ISA = qw(BSE::CustomBase);

# these values are all in cents
my $FREIGHT_OS_FLAG = 500;
my $FREIGHT_OS_PER = 200;
my $FREIGHT_OS_MIN = 600;
my $FREIGHT_AUST_FLAG = 200;
my $FREIGHT_AUST_PER = 50;
my $FREIGHT_AUST_MIN = 300;

my $FREIGHT_AUST_PASS = 400;
my $FREIGHT_OS_PASS = 600;

sub _have_fringe_pass {
  my ($products) = @_;

  scalar(grep $_->{title} =~ /\bpass\b/i, @$products);
}

sub checkout_actions {
  my ($class, $acts, $items, $products) = @_;

  my $want_password = _have_fringe_pass($products);
  
  return
    (
     ifFringePass => sub { $want_password },
    );
}

sub order_save {
  my ($class, $cgi, $order, $items, $products) = @_;

  if (_have_fringe_pass($products)) {
    # the user should have entered as password into the "fringepassword"
    # field
    my $password = $cgi->param('fringepassword');
    my $confirm = $cgi->param('fringepassconfirm');
    unless (defined $password && $password ne '') {
      die "Please enter a password to be used with your Fringe Pass";
    }
    # we only check for confirmation if there was a confirm field
    # on the form
    if (defined($confirm) && $confirm ne $password) {
      die "Your Fringe Pass password does not match the Confirm field";
    }

    use Digest::MD5 qw(md5_hex);
    $order->{billFirstName} = md5_hex($password.$order->{randomId});
  }
}

sub _freight {
  my ($items, $products, $overseas) = @_;

  return 0 if @$items;
  if (grep $products->{title} !~ /pass/i, @$products) {
    my $total = $overseas ? $FREIGHT_OS_FLAG : $FREIGHT_AUST_FLAG;
    my $per = $overseas ? $FREIGHT_OS_PER : $FREIGHT_AUST_PER;
    my $min = $overseas ? $FREIGHT_OS_MIN : $FREIGHT_AUST_MIN;
    my $pass = 0;
    for my $index (0..$#{$items}) {
      if ($products->[$index]{title} =~ /pass/i) {
	$pass = $overseas ? $FREIGHT_OS_PASS : $FREIGHT_AUST_PASS
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

sub total_extras {
  my ($class, $items, $products, $state) = @_;

  _freight($items, $products, $state->{overseas});
}

sub cart_recalc {
  sub ($class, $q, $item, $products, $state) = @_;

  $state->{overseas} = $q->param('overseas');
}

sub cart_actions {
  my ($class, $acts, $items, $products, $state) = @_;

  return
    (
     freight => sub { _freight($items, $products, $state) },
    );
}

1;

=head1 NAME

  BSE::Custom - contains methods you implement to customize the
  behaviour of BSE.

=head1 DESCRIPTION

  See L<BSE::CustomBase> for a list of the methods you can customize.

=cut

