package Squirrel::Template::Expr::WrapScalar;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.007";

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
    or die [ error => "scalar.trim takes no parameters" ];

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

sub _do_evaltag {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.evaltags takes no parameters" ];

  my ($func, $tag_args) = split ' ', $self->[0], 2;

  return $self->[1]->perform($self->[2], $func, $tag_args, $self->[0]);
}

sub _do_quotemeta {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.quotemeta takes no parameters" ];

  return quotemeta($self->[0]);
}

sub _do_contains {
  my ($self, $args) = @_;

  @$args == 1
    or die [ error => "scalar.contains requires one parameter" ];

  return index($self->[0], $args->[0], @$args > 1 ? $args->[1] : 0) >= 0;
}

sub _do_index {
  my ($self, $args) = @_;

  @$args == 1 || @$args == 2
    or die [ error => "scalar.index requires one or two parameters" ];

  return index($self->[0], $args->[0], @$args > 1 ? $args->[1] : 0);
}

sub _do_rindex {
  my ($self, $args) = @_;

  @$args == 1 || @$args == 2
    or die [ error => "scalar.rindex requires one or two parameters" ];

  return @$args > 1
    ? rindex($self->[0], $args->[0], $args->[1])
      :  rindex($self->[0], $args->[0]);
}

sub _do_chr {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.chr takes no parameters" ];

  return chr($self->[0]);
}

sub _do_int {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.int takes no parameters" ];

  return int($self->[0]);
}

sub _do_rand {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.rand takes no parameters" ];

  return rand($self->[0]);
}

sub _do_abs {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.abs takes no parameters" ];

  return abs($self->[0]);
}

sub _do_floor {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.floor takes no parameters" ];

  require POSIX;

  return POSIX::floor($self->[0]);
}

sub _do_ceil {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "scalar.ceil takes no parameters" ];

  require POSIX;

  return POSIX::ceil($self->[0]);
}

sub _do_is_list {
  return 0;
}

sub _do_is_hash {
  return 0;
}

sub _do_is_code {
  my ($self) = @_;

  require Scalar::Util;
  return ref($self->[0]) && Scalar::Util::reftype($self->[0]) eq "CODE";
}

sub _do_replace {
  my ($self, $args) = @_;

  @$args == 2 || @$args == 3
    or die [ error => "scalar.replace takes two or three parameters" ];

  my ($re, $with, $global) = @$args;
  my $str = $self->[0];

  if ($global) {
    $str =~ s{$re}
      {
	# yes, this sucks
	my @out = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
	defined or $_ = '' for @out;
	my $tmp = $with;
	{
	  $tmp =~ s/\$([1-9\$])/
	    $1 eq '$' ? '$' : $out[$1-1] /ge;
	}
	$tmp;
      }ge;
  }
  else {
    $str =~ s{$re}
      {
	# yes, this sucks
	my @out = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
	defined or $_ = '' for @out;
	my $tmp = $with;
	{
	  $tmp =~ s/\$([1-9\$])/
	    $1 eq '$' ? '$' : $out[$1-1] /ge;
	}
	$tmp;
      }e;
  }

  return $str;
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
  value = somescalar.evaltag
  quoted = somescalar.quotemeta
  contains = somescalar.contains("foo")
  pos = somescalar.index("foo")
  pos = somescalar.index("foo", 5)
  pos = somescalar.rindex("foo")
  pos = somescalar.rindex("foo", 5)
  char = somenumber.chr
  int = somenumber.int
  random = somenumber.rand
  abs = (-10).abs  # 10
  floor = (-10.1).floor # -11
  ceil = (-10.1).ceil # -10
  somescalar.is_list # always false
  somescalar.is_hash # always false

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

=item evaltag

Evalulate the value of string as if processed as a tag.  The string
must not include the surrounding <: ... :>.

=item quotemeta

Return the string with regular expression metacharacters quoted with
C<\>.

=item contains(substring)

Returns true if the subject contains the given substring.

=item index(substring)

=item index(substring, start)

Return the position of C<substring> within the subject, searching
forward from C<start> or from the beginning of the string.  Returns -1
if C<substring> isn't found.

=item rindex(substring)

=item rindex(substring, start)

Return the position of C<substring> within the subject, searching
backward from C<start> or from the end of the string.  Returns -1 if
C<substring> isn't found.

=item replace(regexp, replacement)

=item replace(regexp, replacement, global)

Replace the given C<regexp> in the string with C<replacement>. C<$1>
etc are replaced with what the corresponding parenthesized expression
in the regexp matched.  C<$$> is replaced with C<$>.

If C<global> is present and true, replace every instance.

Does not modify the source, simply returns the modified text.

=item chr

Convert a character code into a character.

  (65).chr # "A"

=item int

Convert a number to an integer.

  (10.1).int # 10

=item rand

Produce a floating point random number greater or equal to 0 and less
than the subject.

  (10).rand # 0 <= result < 10

=item abs

Return the absolute value of the subject.

=item floor

Return the highest integer less than or equal to the subject

  (10).floor # 10
  (10.1).floor  # 10
  (-10.1).floor # -11

=item ceil

Return the lowest integer greater than or equal to the subject.

  (10).ceil # 10
  (10.1).ceil # 11
  (-10.1).ceil # -10

=item is_list

Test if this object is a list.  Always true for a list.

=item is_hash

Test if this object is a hash.  Always false for a list.

=item is_code

Test if this object is a code object.

=back

=head1 SEE ALSO

L<Squirrel::Template::Expr>, L<Squirrel::Template>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=back
