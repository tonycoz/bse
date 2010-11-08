package BSE::TB::SeminarBookings;
use strict;
use base qw(Squirrel::Table);
use BSE::TB::SeminarBooking;

our $VERSION = "1.000";

sub rowClass { 'BSE::TB::SeminarBooking' }

1;
