package BSE::TB::Subscription;
use strict;
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

our $VERSION = "1.001";

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

  require BSE::TB::Products;
  BSE::TB::Products->getSpecial(subscriptionDependent => $self->{subscription_id}, 
		       $self->{subscription_id});
}

sub order_summary {
  my ($self) = @_;

  BSE::DB->query(subscriptionOrderSummary=>$self->{subscription_id});
}

sub subscribed_user_summary {
  my ($self) = @_;

  BSE::DB->query(subscriptionUserSummary => $self->{subscription_id});
}

my @expiry_cols = qw(subscription_id siteuser_id started_at ends_at);

sub update_user_expiry {
  my ($self, $user, $cfg) = @_;

  my $debug = $cfg->entry('debug', 'subscription_expiry', 0);

  # gather the orders/items this user has bought for this sub
  my @sub_info = sort { $a->{orderDate} cmp $b->{orderDate} }
    BSE::DB->query(subscriptionUserBought => 
		   $self->{subscription_id}, $user->{id});

  if (@sub_info) {
    require BSE::TB::Subscription::Calc;

    my @periods = BSE::TB::Subscription::Calc->calculate_period
      ($debug, @sub_info);

    my $period = $periods[-1];

    # remove the old one
    BSE::DB->run(removeUserSubscribed => $self->{subscription_id}, 
		 $user->{id});

    # put it back
    BSE::DB->run(addUserSubscribed =>  $self->{subscription_id}, 
		 $user->{id}, $period->{start}, $period->{end},
		 $period->{max_lapsed});
  }
  else {
    # user not subscribed in any way
    BSE::DB->run(removeUserSubscribed => $self->{subscription_id}, 
		 $user->{id});
  }
}

1;
