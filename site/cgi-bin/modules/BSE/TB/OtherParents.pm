package BSE::TB::OtherParents;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::OtherParent;

our $VERSION = "1.001";

sub rowClass {
  return 'BSE::TB::OtherParent';
}

sub anylinks {
  my ($class, $id) = @_;

  $class->getSpecial('anylinks', $id, $id);
}

1;
