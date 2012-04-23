package Squirrel::Template::Expr::WrapBase;
use strict;
our $VERSION = "1.000";

sub new {
  my ($class, $item) = @_;

  return bless [ $item ], $class;
}

1;
