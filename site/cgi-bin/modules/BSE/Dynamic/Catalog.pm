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
     ifDynAnyProductOptions => [ tag_ifDynAnyProductOptions => $self ],
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

sub tag_ifDynAnyProductOptions {
  my ($self, $arg) = @_;

  $arg ||= "dynallprod";

  my $prod = $self->{req}->get_article($arg)
    or return 0;
  $prod->can("option_descs")
    or return 0;
  my @options = $prod->option_descs($self->{req}->cfg);

  return scalar(@options);
}

1;
