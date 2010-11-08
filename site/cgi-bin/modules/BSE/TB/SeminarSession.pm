package BSE::TB::SeminarSession;
use strict;
use base qw(Squirrel::Row);
use BSE::Util::SQL qw(now_sqldatetime);

our $VERSION = "1.000";

sub columns {
  return qw/id seminar_id location_id when_at roll_taken/;
}

sub booked_users {
  my ($self) = @_;

  require SiteUsers;
  return SiteUsers->getSpecial(sessionBookings => $self->{id});
}

# perhaps this should allow removing old sessions with no bookings
sub is_removable {
  my ($self) = @_;

  return $self->{when_at} gt now_sqldatetime();
}

sub seminar {
  my ($self) = @_;

  require BSE::TB::Seminars;

  return BSE::TB::Seminars->getByPkey($self->{seminar_id});
}

sub location {
  my ($self) = @_;
  
  require BSE::TB::Locations;
  return BSE::TB::Locations->getByPkey($self->{location_id});
}

sub replace_with {
  my ($self, $other) = @_;

  # ideally we could just update the column, but that has 2 problems:
  #  - the user might be booked in both the original and new session
  #  - this would be changing the primary key of a record, which is bad
  my %conflicts = map { $_->{id} => 1 }
    BSE::DB->query(conflictSeminarSessions => $self->{id}, $other->{id});
  my @users_booked = map $_->{siteuser_id},
    BSE::DB->query(seminarSessionBookedIds => $self->{id});
  for my $userid (@users_booked) {
    unless ($conflicts{$userid}) {
      BSE::DB->run(seminarSessionBookUser => $other->{id}, $userid, 0);
    }
  }
  BSE::DB->run(cancelSeminarSessionBookings => $self->{id});
  
  $self->remove;
}

sub cancel {
  my ($self) = @_;

  BSE::DB->run(cancelSeminarSessionBookings => $self->{id});
  $self->remove;
}

sub roll_call_entries {
  my ($self) = @_;

  BSE::DB->query(seminarSessionRollCallEntries => $self->{id});
}

sub set_roll_present {
  my ($self, $userid, $present) = @_;

  $present = $present ? 1 : 0;

  BSE::DB->run(updateSessionRollPresent => $present, $self->{id}, $userid);
}

my @attendee_attributes = 
  qw/roll_present options customer_instructions support_notes/;
my %attendee_defaults =
  (
   roll_present => 0,
   options => '',
   customer_instructions => '',
   support_notes => '',
  );

sub add_attendee {
  my ($self, $user, %attr) = @_;

  my %work_attr = %attendee_defaults;
  for my $key (keys %attr) {
    exists $work_attr{$key} or 
      Carp::confess("Unknown attendee attribute '$key'");
    $work_attr{$key} = $attr{$key};
  }

  my $user_id = ref $user ? $user->{id} : $user;

  require BSE::TB::SeminarBookings;
  BSE::TB::SeminarBookings->add($self->{id}, $user_id, 
	       @work_attr{@attendee_attributes});
}

sub get_booking {
  my ($self, $user) = @_;

  my $siteuser_id = ref $user ? $user->{id} : $user;

  require BSE::TB::SeminarBookings;
  my @result = BSE::TB::SeminarBookings->
    getBy(session_id => $self->{id}, siteuser_id => $siteuser_id);
  @result or return;

  return $result[0];
}

sub remove_booking {
  my ($self, $user) = @_;

  my $siteuser_id = ref $user ? $user->{id} : $user;

  my $result = BSE::DB->run
    (bse_cancelSessionBookingForUser => $self->{id}, $siteuser_id);
  $result
    or die "No such booking\n";
}

sub update_booking {
  my ($self, $user, %attr) = @_;

  my $have_all = !grep !exists$attr{$_}, @attendee_attributes;
  unless ($have_all) {
    my $old_booking = $self->get_booking($user)
      or die "No such booking\n";
    %attr = ( %$old_booking, %attr );
  }
  
  my $siteuser_id = ref $user ? $user->{id} : $user;

  BSE::DB->run(bse_updateSessionBookingForUser =>
	       @attr{@attendee_attributes},
	       $self->{id}, $siteuser_id) 
      or die "No such booking\n";

  return 1;
}

1;

