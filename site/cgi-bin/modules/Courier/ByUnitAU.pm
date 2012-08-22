package Courier::ByUnitAU;

our $VERSION = "1.000";

use strict;
use Courier;

our @ISA = qw(Courier);

sub _config {
  my ($self, $key, $def) = @_;

  return $self->{config}->entry("by unit au shipping", $key, $def);
}

sub name {
  my ($self) = @_;

  return $self->_config("name", "by-unit-au");
}

sub description {
  my ($self) = @_;

  return $self->_config("description", "no description set in [by unit au shipping]");
}

sub can_deliver {
  my ($self, %opts) = @_;

  return $opts{country} && $opts{country} eq "AU";
}

sub calculate_shipping {
  my ($self, %opts) = @_;

  my $base = $self->_config("base");

  unless (defined $base) {
    $self->{error} = "No base set in [by unit au shipping]";
    return;
  }

  my $perunit = $self->_config("perunit");

  unless (defined $perunit) {
    $self->{error} = "No perunit set in [by unit au shipping]";
    return;
  }

  my $units = 0;
  for my $item (@{$opts{items}}) {
    $units += $item->{units};
  }

  return $base + ($units - 1) * $perunit;;
}

1;

=head1 NAME

Courier::ByUnitAU - cost per unit shipping within Australia

=head1 SYNOPSIS

  [shipping]
  couriers=ByUnitAU

  [by unit au shipping]
  description=your description here
  base=1000
  perunit=100

=head1 DESCRIPTION

Courier::ByUnitAU provides a common cost per unit to Australia shipping
option for BSE.

=head1 SHIPPING CALCULATION

The shipping cost is calculated based on the number of units in the
order, ie. the sum of the unit value in the line items.  It is
calculated as:

=over

price = base + (units - 1) * perunit

=back

So an order with a single item costs I<base> to send.

=head1 CONFIGURATION

Configuration is done within the C<[by unit au shipping]> section:

=over

=item *

name - internal id of the shipper.  Default: C<by-unit-au>.  Typically
does not need to be set.

=item *

description - the description of the shipping option displayed to the
customer.  Default: "no description set in [by unit au shipping]"

=item *

base - the base cost of shipping in cents.  Must be set.

=item *

perunit - the cost in cents of extra units in the order.  Must be set.
May be zero in which case this becomes equivalent to the Courier::FixedAU
module.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
