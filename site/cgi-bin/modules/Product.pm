package Product;
use strict;
# represents a product from the database
use Article;
use vars qw/@ISA/;
@ISA = qw/Article/;

sub columns {
  return ($_[0]->SUPER::columns(), 
	  qw/articleId summary leadTime retailPrice wholesalePrice gst options
             subscription_id subscription_period subscription_usage
             subscription_required/ );
}

sub bases {
  return { articleId=>{ class=>'Article'} };
}

sub subscription_required {
  my ($self) = @_;

  my $id = $self->{subscription_required};
  return if $id == -1;

  require BSE::TB::Subscriptions;
  return BSE::TB::Subscriptions->getByPkey($id);
}

1;
