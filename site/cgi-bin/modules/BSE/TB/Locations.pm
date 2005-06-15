package BSE::TB::Locations;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Location;

sub rowClass {
  return 'BSE::TB::Location';
}

1;
