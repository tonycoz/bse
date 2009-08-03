package Courier::Fastway::Road;

use strict;
use Courier::Fastway;

our @ISA=qw(Courier::Fastway);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "Road");
}

sub name {
    "fastway-road"
}

sub description {
    "Fastway Road Service"
}

sub weight_limit {
  25;
}

sub _find_result {
  my ($self, $props) = @_;

  $props->{road} and return $props->{road};
  $props->{local} and return $props->{local};
  return;
}

1;
