package Squirrel::Template::Expr::WrapBase;
use strict;
our $VERSION = "1.001";

sub new {
  my ($class, $item, $templater, $acts) = @_;

  return bless [ $item, $templater, $acts ], $class;
}

1;
