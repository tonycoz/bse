package Courier::FixedAU;

our $VERSION = "1.000";

use strict;
use Courier;

our @ISA = qw(Courier);

sub _config {
  my ($self, $key, $def) = @_;

  return $self->{config}->entry("fixed au shipping", $key, $def);
}

sub name {
  my ($self) = @_;

  return $self->_config("name", "fixed-au");
}

sub description {
  my ($self) = @_;

  return $self->_config("description", "no description set in [fixed au shipping]");
}

sub can_deliver {
  my ($self, %opts) = @_;

  return $opts{country} && $opts{country} eq "AU";
}

sub calculate_shipping {
  my ($self, %opts) = @_;
  
  my $price = $self->_config("price");

  unless (defined $price) {
    $self->{error} = "No price set in [fixed au shipping]";
    return;
  }

  return $price;
}

1;

=head1 NAME

Courier::FixedAU - fixed price shipping within Australia

=head1 SYNOPSIS

  [shipping]
  couriers=FixedAU

  [fixed au shipping]
  description=your description here
  price=1000

=head1 DESCRIPTION

Courier::FixedAU provides a common fixed price to Australia shipping
option for BSE.

=head1 CONFIGURATION

Configuration is done within the C<[fixed au shipping]> section:

=over

=item *

name - internal id of the shipper.  Default: C<fixed-au>.  Typically
does not need to be set.

=item *

description - the description of the shipping option displayed to the
customer.  Default: "no description set in [fixed au shipping]"

=item *

price - the price in cents to charge for shipping.  Must be set.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
