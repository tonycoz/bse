package Products;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use Product;

sub rowClass {
  return 'Product';
}

1;
