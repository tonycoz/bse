package BSE::Dynamic::Product;
use strict;
use base 'BSE::Dynamic::Article';
use Products;

our $VERSION = "1.000";

sub get_real_article {
  my ($self, $article) = @_;

  Products->getByPkey($article->{id});
}

sub tags {
  my ($self, $article) = @_;

  return
    (
     $self->SUPER::tags($article),
     ifInWishlist => [ tag_ifInWishlist => $self, $article ],
    );
}

sub tag_ifInWishlist {
  my ($self, $article) = @_;

  my $user = $self->{req}->siteuser
    or return 0;

  return $user->product_in_wishlist($article);
}

1;
