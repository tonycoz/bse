package BSE::SubscribedUser;
use strict;
# represents the user <-> subscription relation from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id subId userId/;
}

1;
