package ArticleFiles;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use ArticleFile;

sub rowClass {
  return 'ArticleFile';
}

1;
