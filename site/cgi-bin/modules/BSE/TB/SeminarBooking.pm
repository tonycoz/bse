package BSE::TB::SeminarBooking;
use strict;
use base qw(Squirrel::Row);

our $VERSION = "1.001";

sub columns {
  qw/id session_id siteuser_id roll_present options customer_instructions 
     support_notes/;
}

sub session {
  my ($self) = @_;

  require BSE::TB::SeminarSessions;

  return BSE::TB::SeminarSessions->getByPkey($self->{session_id});
}

sub siteuser {
  my ($self) = @_;

  require BSE::TB::SiteUsers;

  return BSE::TB::SiteUsers->getByPkey($self->{siteuser_id});
}

1;
