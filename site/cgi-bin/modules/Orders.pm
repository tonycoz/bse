package Orders;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);

our $VERSION = "1.000";

sub rowClass {
  return 'Order';
}

1;
