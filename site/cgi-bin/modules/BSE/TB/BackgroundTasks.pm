package BSE::TB::BackgroundTasks;
use strict;
use base 'Squirrel::Table';
use BSE::TB::BackgroundTask;

sub rowClass {
  'BSE::TB::BackgroundTask';
}

1;
