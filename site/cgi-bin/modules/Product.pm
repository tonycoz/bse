package Product;
use strict;
# represents a product from the database
use Article;
use vars qw/@ISA/;
@ISA = qw/Article/;

# subscription_usage values
use constant SUBUSAGE_START_ONLY => 1;
use constant SUBUSAGE_RENEW_ONLY => 2;
use constant SUBUSAGE_EITHER => 3;

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

sub subscription {
  my ($self) = @_;

  my $id = $self->{subscription_id};
  return if $id == -1;

  require BSE::TB::Subscriptions;
  return BSE::TB::Subscriptions->getByPkey($id);
}

sub is_renew_sub_only {
  my ($self) = @_;

  $self->{subscription_usage} == SUBUSAGE_RENEW_ONLY;
}

sub is_start_sub_only {
  my ($self) = @_;

  $self->{subscription_usage} == SUBUSAGE_START_ONLY;
}

1;
