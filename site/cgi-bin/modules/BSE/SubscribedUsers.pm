package BSE::SubscribedUsers;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::SubscribedUser;

sub rowClass {
  return 'BSE::SubscribedUser';
}

1;
