package OtherParents;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use OtherParent;

our $VERSION = "1.000";

sub rowClass {
  return 'OtherParent';
}

sub anylinks {
  my ($class, $id) = @_;

  $class->getSpecial('anylinks', $id, $id);
}

1;
