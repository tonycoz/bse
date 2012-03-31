package Squirrel::Template::Expr::WrapScalar;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.000";

sub _do_length  {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.length takes no parameters" ];

  return length $self->[0];
}

sub _do_upper {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.upper takes no parameters" ];

  return uc $self->[0];
}

sub _do_lower {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.lower takes no parameters" ];

  return lc $self->[0];
}

sub _do_defined {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.defined takes no parameters" ];

  return defined $self->[0];
}

sub _do_trim {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.defined takes no parameters" ];

  my $copy = $self->[0];
  $copy =~ s/\A\s+//;
  $copy =~ s/\s+\z//;

  return $copy;
}

sub _do_split {
  my ($self, $args) = @_;

  my $split = @$args ? $args->[0] : " ";
  my $limit = @$args >= 2 ? $args->[1] : 0;

  return [ split $split, $self->[0], $limit ];
}

sub _do_format {
  my ($self, $args) = @_;

  @$args == 1
    or die [ error => "scalar.format takes one parameter" ];

  return sprintf($args->[0], $self->[0]);
}

sub call {
  my ($self, $method, $args) = @_;

  my $real_method = "_do_$method";
  if ($self->can($real_method)) {
    return $self->$real_method($args);
  }
  die [ error => "No method $method for scalars" ];
}

1;
