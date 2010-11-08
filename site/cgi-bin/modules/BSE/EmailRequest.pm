package BSE::EmailRequest;
use strict;
# represents a subscription type from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

our $VERSION = "1.000";

sub columns {
  return qw/id email genEmail lastConfSent unackedConfMsgs/;
}

1;
