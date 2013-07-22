package BSE::TB::CouponTiers;
use strict;
use Squirrel::Table;
our @ISA = qw(Squirrel::Table);
use BSE::TB::CouponTier;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::CouponTier';
}

1;
