package Orders;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);

sub rowClass {
  return 'Order';
}

1;
