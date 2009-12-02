package BSE::TB::Images;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Image;

sub rowClass {
  return 'BSE::TB::Image';
}

sub image_storages {
  return map [ $_->{image}, $_->{storage}, $_ ], BSE::TB::Images->all;
}

1;
