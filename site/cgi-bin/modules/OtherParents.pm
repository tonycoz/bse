package OtherParents;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use OtherParent;

sub rowClass {
  return 'OtherParent';
}

sub anylinks {
  my ($class, $id) = @_;

  $class->getSpecial('anylinks', $id, $id);
}

1;
