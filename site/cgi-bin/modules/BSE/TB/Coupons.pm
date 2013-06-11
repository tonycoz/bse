package BSE::TB::Coupons;
use strict;
use Squirrel::Table;
our @ISA = qw(Squirrel::Table);
use BSE::TB::Coupon;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::Coupon';
}

sub make {
  my ($self, %opts) = @_;

  my $tiers = delete $opts{tiers};

  my $coupon = $self->SUPER::make(%opts);

  if ($tiers) {
    $coupon->set_tiers($tiers);
  }

  return $coupon;
}

1;
