package Squirrel::Template::Expr::WrapClass;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.001";

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

__END__

=head1 NAME

Squirrel::Template::Expr::WrapClass - wrap class names

=head1 SYNOPSIS

  my $cls_object = Squirrel::Template::Expr::WrapClass->new($class_name);

=head1 DESCRIPTION

Since perl has no class objects as such, this class produces a wrapper
object so expression evaluation can distinguish classes from scalars
that are intended to be treated as such.

If the underlying class has a restricted_method() method, it is called
to check whether expression evaluation is permitted to call the
method.

=head1 SEE ALSO

L<Squirrel::Template::Expr>, L<Squirrel::Template>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
