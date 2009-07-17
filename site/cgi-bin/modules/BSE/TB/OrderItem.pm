package BSE::TB::OrderItem;
use strict;
# represents an order line item from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id productId orderId units price wholesalePrice gst options
            customInt1 customInt2 customInt3 customStr1 customStr2 customStr3
            title description subscription_id subscription_period max_lapsed
            session_id product_code/;
}

sub option_list {
  my ($self) = @_;

  require BSE::TB::OrderItemOptions;
  return sort { $a->{display_order} <=> $b->{display_order} }
    BSE::TB::OrderItemOptions->getBy(order_item_id => $self->{id});
}

1;
