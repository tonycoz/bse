package BSE::TB::SeminarSession;
use strict;
use base qw(Squirrel::Row);
use BSE::Util::SQL qw(now_sqldatetime);

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

  BSE::DB->run(seminarSessionBookUser => $self->{id}, $user_id, 
	       @work_attr{@attendee_attributes});
}

1;

