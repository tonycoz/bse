package Images;

use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use Image;

sub rowClass {
  return 'Image';
}

1;
