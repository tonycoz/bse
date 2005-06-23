package BSE::TB::SeminarSessions;
use strict;
use base 'Squirrel::Table';
use BSE::TB::SeminarSession;

sub rowClass { 'BSE::TB::SeminarSession' }

1;
