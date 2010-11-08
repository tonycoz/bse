package BSE::TB::OrderItems;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::OrderItem;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::OrderItem';
}

1;
