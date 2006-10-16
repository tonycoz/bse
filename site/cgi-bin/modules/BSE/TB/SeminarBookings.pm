package BSE::TB::SeminarBookings;
use strict;
use base qw(Squirrel::Table);
use BSE::TB::SeminarBooking;

sub rowClass { 'BSE::TB::SeminarBooking' }

1;
