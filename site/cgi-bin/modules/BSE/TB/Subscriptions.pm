package BSE::TB::Subscriptions;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Subscription;

sub rowClass {
  return 'BSE::TB::Subscription';
}

sub calculate_all_expiries {
  my ($class, $cfg) = @_;

  require SiteUsers;
  
  # get a list of all siteusers that have made an order with a subscription
  my @users = SiteUsers->all_subscribers;

  my @subs = $class->all;

  for my $user (@users) {
    for my $sub (@subs) {
      $sub->update_user_expiry($user, $cfg);
    }
  }
}

1;
