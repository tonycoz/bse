package BSE::TB::Locations;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Location;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::Location';
}

1;
