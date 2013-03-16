package BSE::TB::IPLockout;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.000";

sub columns {
  qw(id ip_address type expires);
}

sub table {
  "bse_ip_lockouts";
}

1;
