package BSE::TB::Subscription;
use strict;
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/subscription_id text_id title description max_lapsed/;
}

sub primary { 'subscription_id' }

# call as a method for edits
sub valid_rules {
  my ($self, $cfg) = @_;

  my @subs = BSE::TB::Subscriptions->all;
  if (ref $self) {
    @subs = grep $_->{subscription_id} != $self->{subscription_id}, @subs;
  }
  my $notsubid_match = join '|', map $_->{text_id}, @subs;

  return
    (
     identifier => { match => qr/^\w+$/,
		   error => '$n must contain only letters and digits, and no spaces' },
     notsubid => { nomatch => qr/^(?:$notsubid_match)$/,
		 error => 'Duplicate identifier' },
    );
}

sub valid_fields {
  return
    (
     text_id => { description=>"Identifier", 
		  rules=>'required;identifier;notsubid' },
     title => { description=>"Title",
		required => 1 },
     description => { description=>"Description" },
     max_lapsed => { description => 'Max lapsed', 
		     rules => 'required;natural', },
    );
}

sub is_removable {
  my ($self, $rmsg) = @_;

  # can only remove if no products use it and no existing orders refer
  # to it
  if ($self->product_count) {
    $$rmsg = "There are products using this subscription, it cannot be deleted"
      if $rmsg;
    return;
  }
  if ($self->order_item_count) {
    $$rmsg = "There are orders that include this subscription, it cannot be deleted"
      if $rmsg;
    return;
  }

  return 1;
}

sub product_count {
  my ($self) = @_;

  my ($row) = BSE::DB->query(subscriptionProductCount => 
			     $self->{subscription_id}, $self->{subscription_id});

  return $row->{count};
}

sub order_item_count {
  my ($self) = @_;

  my ($row) = BSE::DB->query(subscriptionOrderItemCount => 
			     $self->{subscription_id});

  return $row->{count};
}

sub dependent_products {
  my ($self) = @_;

  require Products;
  Products->getSpecial(subscriptionDependent => $self->{subscription_id}, 
		       $self->{subscription_id});
}

sub order_summary {
  my ($self) = @_;

  BSE::DB->query(subscriptionOrderSummary=>$self->{subscription_id});
}

1;
