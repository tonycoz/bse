package OrderItem;

# represents an order line item from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

sub columns {
  return qw/id productId orderId units price wholesalePrice gst options/;
}

1;
