package BSE::TB::SeminarSessions;
use strict;
use base 'Squirrel::Table';
use BSE::TB::SeminarSession;

our $VERSION = "1.000";

sub rowClass { 'BSE::TB::SeminarSession' }

1;
