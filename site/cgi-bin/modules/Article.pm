package Article;
use strict;
# represents an article from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id parentid displayOrder title titleImage body
    thumbImage thumbWidth thumbHeight imagePos
    release expire keyword template link admin threshold
    summaryLength generator level listed lastModified/;
}

sub step_parents {
  my ($self) = @_;

  Articles->getSpecial('stepParents', $self->{id});
}

1;
