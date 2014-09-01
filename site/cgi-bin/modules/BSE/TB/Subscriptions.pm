package BSE::TB::Subscriptions;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Subscription;

our $VERSION = "1.001";

sub rowClass {
  return 'BSE::TB::Subscription';
}

sub calculate_all_expiries {
  my ($class, $cfg) = @_;

  require BSE::TB::SiteUsers;
  
  # get a list of all siteusers that have made an order with a subscription
  my @users = BSE::TB::SiteUsers->all_subscribers;

  my @subs = $class->all;

  for my $user (@users) {
    for my $sub (@subs) {
      $sub->update_user_expiry($user, $cfg);
    }
  }
}

1;
