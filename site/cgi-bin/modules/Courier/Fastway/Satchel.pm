package Courier::Fastway::Satchel;

use strict;
use Courier::Fastway;

our @ISA=qw(Courier::Fastway);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "Satchel");
}

sub name {
    "fastway-satchel"
}

sub description {
    "Fastway Satchel Service"
}

sub weight_limit {
  3;
}

sub _find_result {
  my ($self, $props) = @_;

  $props->{satchel} and return $props->{satchel};

  return;
}

1;
