package BSE::TB::TagCategories;
use strict;
use base 'Squirrel::Table';
use BSE::TB::TagCategory;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::TagCategory';
}

1;
