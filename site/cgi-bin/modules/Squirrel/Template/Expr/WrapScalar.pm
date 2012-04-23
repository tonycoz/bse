package Squirrel::Template::Expr::WrapScalar;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.001";

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

=head1 NAME

Squirrel::Template::Expr::WrapScalar - provide methods for scalars

=head1 SYNOPSIS

  len = somescalar.length;
  upper = somescalar.upper;
  lower = somescalar.lower;
  defd = somescalar.defined;
  trimmed = somescalar.trim;
  split = somescalar.split;
  split = somescalar.split(":");
  split = somescalar.split(":", count);
  formatted = somescalar.format("%05d");

=head1 DESCRIPTION

Provides virtual methods for scalars in L<Squirrel::Template>
expressions.

=head1 SCALAR METHODS

=over

=item length

Return the length of the string in characters.

=item upper

Return the string in upper case

=item lower

Return the string in lower case.

=item defined

Return true if the string has a defined value.

=item split

=item split(sep)

=item split(sep, count)

Return a list object of the string split on the regular expression
C<sep>, returning up to C<count> objects.  C<sep> defaults to C<" ">,
C<count> defaults to C<0>.  A count of C<0> returns as many elements
as are found but removes any trailing empty length elements.  A
negative C<count> returns all elements.

=head1 SEE ALSO

L<Squirrel::Template::Expr>, L<Squirrel::Template>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=back
