package Image;

# represents an image from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id articleId image alt width height url/;
}

1;
