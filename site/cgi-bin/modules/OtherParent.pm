package OtherParent;
use strict;
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

# id is only needed due to limitations in BSE's Squirrel::Row
sub columns {
  qw/id parentId childId parentDisplayOrder childDisplayOrder release expire/;
}

1;
