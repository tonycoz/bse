package BSE::TB::Seminars;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Seminar;

sub rowClass {
  return 'BSE::TB::Seminar';
}

1;
