package BSE::TB::BackgroundTasks;
use strict;
use base 'Squirrel::Table';
use BSE::TB::BackgroundTask;

our $VERSION = "1.000";

sub rowClass {
  'BSE::TB::BackgroundTask';
}

1;
