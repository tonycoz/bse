package BSE::TB::OrderItem;
use strict;
# represents an order line item from the database
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;

our $VERSION = "1.003";

sub columns {
  return qw/id productId orderId units price wholesalePrice gst options
            customInt1 customInt2 customInt3 customStr1 customStr2 customStr3
            title description subscription_id subscription_period max_lapsed
            session_id product_code/;
}

sub defaults {
  return
    (
     units => 1,
     options => '',
     customInt1 => undef,
     customInt2 => undef,
     customInt3 => undef,
     customStr1 => undef,
     customStr2 => undef,
     customStr3 => undef,
    );
}

sub option_list {
  my ($self) = @_;

  require BSE::TB::OrderItemOptions;
  return sort { $a->{display_order} <=> $b->{display_order} }
    BSE::TB::OrderItemOptions->getBy(order_item_id => $self->{id});
}

sub product {
  my ($self) = @_;

  $self->productId == -1
    and return;
  require Products;
  return Products->getByPkey($self->productId);
}

sub option_hashes {
  my ($self) = @_;

  my $product = $self->product;
  if (length $self->{options}) {
    my @values = split /,/, $self->options;
    return map
      +{
	id => $_->{id},
	value => $_->{value},
	desc => $_->{desc},
	label => $_->{display},
       }, $product->option_descs(BSE::Cfg->single, \@values);
  }
  else {
    my @options = $self->option_list;
    return map
      +{
	id => $_->original_id,
	value => $_->value,
	desc => $_->name,
	label => $_->display
       }, @options;
  }
}

sub nice_options {
  my ($self) = @_;

  my @options = $self->option_hashes
    or return '';

  return '('.join(", ", map("$_->{desc} $_->{label}", @options)).')';
}

sub session {
  my ($self) = @_;

  $self->session_id
    or return;

  require BSE::TB::SeminarSessions;
  return BSE::TB::SeminarSessions->getByPkey($self->session_id);
}

# cart item compatibility
sub retailPrice {
  $_[0]->price;
}

sub extended {
  my ($self, $name) = @_;

  return $self->units * $self->$name();
}

1;
