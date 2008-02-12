package ArticleFiles;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use ArticleFile;

sub rowClass {
  return 'ArticleFile';
}

sub file_storages {
  my $self = shift;
  return map [ $_->{filename}, $_->{storage}, $_ ], $self->all;
}

1;
