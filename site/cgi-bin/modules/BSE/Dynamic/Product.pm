package BSE::Dynamic::Product;
use strict;
use base 'BSE::Dynamic::Article';
use Products;

sub get_real_article {
  my ($self, $article) = @_;

  Products->getByPkey($article->{id});
}

1;
