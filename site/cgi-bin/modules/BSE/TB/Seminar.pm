package BSE::TB::Seminar;
use strict;
# represents a seminar from the database
use Product;
use vars qw/@ISA/;
@ISA = qw/Product/;
use BSE::Util::SQL qw(now_sqldatetime);

sub columns {
  return ($_[0]->SUPER::columns(), 
	  qw/seminar_id duration/ );
}

sub bases {
  return { seminar_id=>{ class=>'Product'} };
}

sub sessions {
  my ($self) = @_;

  require BSE::TB::SeminarSessions;
  BSE::TB::SeminarSessions->getBy(session_id => $self->{id});
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

1;
