package BSE::Dynamic::Seminar;
use strict;
use base 'BSE::Dynamic::Product';
use BSE::TB::Seminars;

our $VERSION = "1.000";

sub get_real_article {
  my ($self, $article) = @_;

  BSE::TB::Seminars->getByPkey($article->{id});
}

1;
