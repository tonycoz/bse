package OrderItems;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);

sub rowClass {
  return 'OrderItem';
}

1;
