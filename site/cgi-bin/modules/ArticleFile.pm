package ArticleFile;
use strict;
# represents a file associated with an article from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id articleId displayName filename sizeInBytes description 
            contentType displayOrder forSale download whenUploaded/;
}

1;
