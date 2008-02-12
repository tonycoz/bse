package Images;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use Image;

sub rowClass {
  return 'Image';
}

sub image_storages {
  return map [ $_->{image}, $_->{storage}, $_ ], Images->all;
}

1;
