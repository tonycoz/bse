package Courier;

use strict;
use LWP::UserAgent;

sub new {
    my $class = shift;
    my $self = {};
    my %args = @_;

    @$self{qw(cost days error trace)} = undef;
    $self->{config} = $args{config};
    $self->{type} = $args{type};
    $self->{ua} = LWP::UserAgent->new;
    return bless $self, $class;
}

sub name {
    # Implemented by subclasses
}

sub description {
    # Implemented by subclasses
}

sub can_deliver {
  # Implemented by subclasses
  # accepts:
  # country - country code for delivery
  # suburb - suburb name for delivery
  # postcode - postcode for delivery
  return 0;
}

sub calculate_shipping {
  # Implemented by subclasses
  # accepts:
  # parcels - array ref of BSE::Shipping::Parcel objects
  # country - country code for delivery
  # suburb, postcode - delivery location
}

sub delivery_in {
    my ($self) = @_;
    return $self->{days};
}

sub error_message {
    my ($self) = @_;
    return $self->{error};
}

sub trace {
    $_[0]{trace};
}


1;
