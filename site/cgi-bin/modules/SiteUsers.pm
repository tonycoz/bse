package SiteUsers;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use SiteUser;

sub rowClass {
  return 'SiteUser';
}

1;
