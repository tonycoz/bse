package BSE::TB::PriceTier;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.000";

sub columns {
  return qw(id description group_id from_date to_date display_order);
}

sub table {
  return "bse_price_tiers";
}

sub defaults {
  return
    (
     group_id => undef,
     from_date => undef,
     to_date => undef,
     display_order => time,
    );
}

=item match($user, $date)

Match the C<$user> and C<$date> against the contraints for this tier.

Returns true if all constraints pass.

=cut

sub match {
  my ($self, $user, $date) = @_;

  if (my $from = $self->from_date) {
    $date lt $from and return;
  }

  if (my $to = $self->to_date) {
    $date gt $to and return;
  }

  if ($self->group_id) {
    $user or return;

    require BSE::TB::SiteUserGroups;
    my $group = BSE::TB::SiteUserGroups->getById($self->group_id);
    unless ($group) {
      require BSE::TB::AuditLog;
      BSE::TB::AuditLog->log
	  (
	   component => "shop:pricetier:match",
	   level => "crit",
	   actor => "S",
	   msg => "Unknown group id " . $self->group_id . " in price tier " . $self->id,
	   object => $self,
	  );
      return;
    }
    $group->contains_user($user)
      or return;
  }

  return 1;
}

1;
