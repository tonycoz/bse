package BSE::SubscriptionTypes;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::SubscriptionType;

sub rowClass {
  return 'BSE::SubscriptionType';
}

1;
