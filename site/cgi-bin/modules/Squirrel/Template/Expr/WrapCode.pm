package Squirrel::Template::Expr::WrapCode;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.000";

sub call {
  my ($self, $method, $args) = @_;

  return $self->[0]->($method, @$args);
}

1;
