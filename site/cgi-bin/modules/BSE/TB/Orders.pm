package BSE::TB::Orders;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Order;

sub rowClass {
  return 'BSE::TB::Order';
}

1;
