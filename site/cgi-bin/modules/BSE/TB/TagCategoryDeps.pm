package BSE::TB::TagCategoryDeps;
use strict;
use base 'Squirrel::Table';
use BSE::TB::TagCategoryDep;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::TagCategoryDep';
}

1;
