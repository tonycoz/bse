package Squirrel::Template::Params;
use strict;
use base "Squirrel::Template::Expr::WrapBase";
use Scalar::Util ();

our $VERSION = "1.000";

sub new {
  my ($class, @rest) = @_;

  my $self = $class->SUPER::new(@rest);
  Scalar::Util::weaken($self->[1]);

  return $self;
}

sub call {
  my ($self, $method, $args) = @_;

  return $self->[1]->tag_param($method);
}

1;
