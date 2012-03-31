package Squirrel::Template::Expr::WrapClass;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

sub call {
  my ($self, $method, $args, $ctx) = @_;
  if ($self->[0]->can("restricted_method")) {
    $self->[0]->restricted_method($method)
      and die [ error => "method $method is restricted" ];
  }

  $self->[0]->can($method)
    or die [ error => "No such method $method" ];

  return $ctx eq 'LIST' ? $self->[0]->$method(@$args)
    : scalar $self->[0]->$method(@$args);
}

1;

