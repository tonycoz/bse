package BSE::TB::CouponTier;
use strict;
use Squirrel::Row;
our @ISA = qw/Squirrel::Row/;

our $VERSION = "1.000";

sub columns {
  return qw/id coupon_id tier_id/;
}

sub table {
  "bse_coupon_tiers";
}

1;
