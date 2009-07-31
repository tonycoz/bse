package Courier::Null;

use strict;
use Courier;

our @ISA = qw(Courier);

sub name {
    "contact"
}

sub description {
    "Quote shipping charges later"
}

sub can_deliver {
    return 1;
}

sub calculate_shipping {
    my ($self) = @_;

    $self->{shipping_cost} = 0;
    $self->{error} = "OK";
    $self->{days} = 0;
}

1;
