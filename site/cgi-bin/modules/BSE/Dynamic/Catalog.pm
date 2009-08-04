package BSE::Dynamic::Catalog;
use strict;
use base 'BSE::Dynamic::Article';

# no specific behavious yet

sub tags {
  my ($self, $article) = @_;

  my $allprod_data;
  my $allprod_index;
  my $allcat_data;
  my $allcat_index;
  return
    (
     $self->SUPER::tags($article),
     $self->dyn_article_iterator('dynallprods', 'dynallprod', $article,
				 \$allprod_index, \$allprod_data),
     dynmoveallprod =>
     [ tag_dynmove => $self, \$allprod_index, \$allprod_data, 
       "stepparent=$article->{id}" ],
     $self->dyn_article_iterator('dynallcats', 'dynallcat', $article,
				 \$allcat_index, \$allcat_data),
     dynmoveallcat =>
     [ tag_dynmove => $self, \$allcat_index, \$allcat_data,
       "stepparent=$article->{id}" ],
    );
}

sub iter_dynallprods {
  my ($self, $article, $args) = @_;

  my $result = $self->get_cached('dynallprods');
  $result
    and return $result;

  $result = $self->access_filter($article->all_visible_products);

  $self->set_cached(dynallprods => $result);

  return $result
}

sub iter_dynallcats {
  my ($self, $article, $args) = @_;

  my $result = $self->get_cached('dynallcats');
  $result
    and return $result;

  $result = $self->access_filter($article->all_visible_catalogs);

  $self->set_cached(dynallcats => $result);

  return $result
}

1;
