package BSE::TB::Orders;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Order;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::Order';
}

1;
