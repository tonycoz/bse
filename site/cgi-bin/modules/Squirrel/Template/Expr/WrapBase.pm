package Squirrel::Template::Expr::WrapBase;
use strict;
our $VERSION = "1.002";

sub new {
  my ($class, $item, $templater, $acts, $eval) = @_;

  return bless [ $item, $templater, $acts, $eval ], $class;
}

sub expreval {
  $_[0][3];
}

1;
