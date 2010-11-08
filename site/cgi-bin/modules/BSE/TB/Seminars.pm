package BSE::TB::Seminars;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Seminar;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::Seminar';
}

1;
