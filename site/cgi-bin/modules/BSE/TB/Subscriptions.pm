package BSE::TB::Subscriptions;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Subscription;

sub rowClass {
  return 'BSE::TB::Subscription';
}

1;
