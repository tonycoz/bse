package BSE::TB::Seminar;
use strict;
# represents a seminar from the database
use BSE::TB::Product;
use vars qw/@ISA/;
@ISA = qw/BSE::TB::Product/;
use BSE::Util::SQL qw(now_sqldatetime);

our $VERSION = "1.001";

sub columns {
  return ($_[0]->SUPER::columns(), 
	  qw/seminar_id duration/ );
}

sub bases {
  return { seminar_id=>{ class=>'BSE::TB::Product'} };
}

sub sessions {
  my ($self) = @_;

  require BSE::TB::SeminarSessions;
  BSE::TB::SeminarSessions->getBy(seminar_id => $self->{id});
}

sub future_sessions {
  my ($self) = @_;

  require BSE::TB::SeminarSessions;
  BSE::TB::SeminarSessions->getSpecial(futureSessions => $self->{id}, now_sqldatetime());
}

sub session_info {
  my ($self) = @_;

  BSE::DB->query(seminarSessionInfo => $self->{id});
}

sub session_info_unbooked {
  my ($self, $user) = @_;

  BSE::DB->query(seminarSessionInfoUnbooked => $user->{id}, $self->{id});
}

sub future_session_info {
  my ($self) = @_;

  BSE::DB->query(seminarFutureSessionInfo=>$self->{id}, now_sqldatetime());
}

sub add_session {
  my ($self, $when, $location) = @_;

  require BSE::TB::SeminarSessions;
  my %cols = 
    ( 
     seminar_id => $self->{id},
     when_at => $when,
     location_id => ref $location ? $location->{id} : $location,
     roll_taken => 0,
    );
  my @cols = BSE::TB::SeminarSession->columns;
  shift @cols;
  return BSE::TB::SeminarSessions->add(@cols{@cols});
}

sub future_locations {
  my ($self) = @_;

  require BSE::TB::Locations;
  return BSE::TB::Locations->getSpecial
    (seminarFuture => $self->{id}, now_sqldatetime());
}

sub future_location_sessions {
  my ($self, $location) = @_;

  require BSE::TB::SeminarSessions;
  return BSE::TB::SeminarSessions->getSpecial
    (futureSeminarLocation => $self->{id}, $location->{id}, now_sqldatetime());
}

sub get_unbooked_by_user {
  my ($self, $user) = @_;

  require BSE::TB::SeminarSessions;
  BSE::TB::SeminarSessions->getSpecial(sessionsUnbookedByUser => 
				       $user->{id}, $self->{id});
}

1;
