package BSE::TB::Coupons;
use strict;
use Squirrel::Table;
our @ISA = qw(Squirrel::Table);
use BSE::TB::Coupon;

our $VERSION = "1.001";

sub rowClass {
  return 'BSE::TB::Coupon';
}

sub make {
  my ($self, %opts) = @_;

  my $tiers = delete $opts{tiers};

  my $coupon = $self->SUPER::make(%opts);

  if ($tiers) {
    $coupon->set_tiers($tiers);
    $coupon->save;
  }

  return $coupon;
}

1;
