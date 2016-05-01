package Squirrel::Template::Expr::WrapScalar;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.011";

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

sub _do_substring {
  my ($self, $args) = @_;

  @$args == 1 || @$args == 2
    or die [ error => "scalar.substring takes 1 or 2 parameters" ];

  return @$args == 1
    ? substr($self->[0], $args->[0])
      : substr($self->[0], $args->[0], $args->[1]);
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
  my $eval = $self->expreval;
  my $with_code =
    ref $with
    ? sub {
      $eval->call_function($with, [ _make_match($str) ])
    }
    : sub {
      # yes, this sucks
      my @out = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
      defined or $_ = '' for @out;
      my $tmp = $with;
      {
	$tmp =~ s/\$([1-9\$])/
	  $1 eq '$' ? '$' : $out[$1-1] /ge;
      }
      $tmp;
    };

  if ($global) {
    $str =~ s{$re}{ $with_code->() }ge;
  }
  else {
    $str =~ s{$re}{ $with_code->() }e;
  }

  return $str;
}

sub _do_match {
  my ($self, $args) = @_;

  @$args == 1
    or die [ error => "scalar.match requires one parameter" ];

  $self->[0] =~ $args->[0]
    or return undef;

  return _make_match($self->[0]);
}

sub _make_match {
  my %match;
  tie %match, 'Squirrel::Template::Expr::WrapScalar::Match', $_[0], \@-, \@+, \%-, \%+;

  \%match;
}

sub _do_escape {
  my ($self, $args) = @_;

  @$args == 1
    or die [ error => "scalar.escape requires one parameter" ];
  return $self->[1]->format($self->[0], $args->[0]);
}

sub call {
  my ($self, $method, $args) = @_;

  my $real_method = "_do_$method";
  if ($self->can($real_method)) {
    return $self->$real_method($args);
  }
  die [ error => "No method $method for scalars" ];
}

package Squirrel::Template::Expr::WrapScalar::Match;
use base 'Tie::Hash';

sub TIEHASH {
  my ($class, $text, $starts, $ends, $nstarts, $nends) = @_;

  bless
    {
     text => $text,
     starts => [ @$starts ],
     ends => [ @$ends ],
     nstarts => +{ %$nstarts },
     nends => +{ %$nends },
     keys => +{ map {; $_ => 1 } qw(text start end length subexpr named) },
    };
}

sub FETCH {
  my ($self, $name) = @_;

  return substr($self->{text}, $self->{starts}[0], $self->{ends}[0] - $self->{starts}[0])
    if $name eq 'text';
  return $self->{starts}[0] if $name eq 'start';
  return $self->{ends}[0] if $name eq 'end';
  return $self->{ends}[0] - $self->{starts}[0] if $name eq 'length';
  if ($name eq 'subexpr') {
    my @subexpr;
    tie @subexpr, 'Squirrel::Template::Expr::WrapScalar::Match::Subexpr',
      $self->{starts}, $self->{ends}, $self->{text};
    return \@subexpr;
  }
  if ($name eq 'named') {
    my %named;
    tie %named, 'Squirrel::Template::Expr::WrapScalar::Match::Named', $self->{nstarts}, $self->{nends};
    return \%named;
  }
  return undef;
}

sub EXISTS {
  my ($self, $name) = @_;

  return exists $self->{keys}{$name};
}

sub FIRSTKEY {
  my ($self) = @_;

  keys %{$self->{keys}};

  each %{$self->{keys}};
}

sub NEXTKEY {
  my ($self) = @_;

  each %{$self->{keys}};
}

package Squirrel::Template::Expr::WrapScalar::Match::Subexpr;
use base 'Tie::Array';

sub TIEARRAY {
  my ($class, $starts, $ends, $text) = @_;

  bless [ $starts, $ends, $text ], $class;
}

sub FETCH {
  my ($self, $index) = @_;

  $index >= 0 && $index < $#{$self->[0]}
    or return undef;

  return
    +{
      start => $self->[0][$index+1],
      end => $self->[1][$index+1],
      length => $self->[1][$index+1] - $self->[0][$index+1],
      text => substr($self->[2], $self->[0][$index+1],
		     $self->[1][$index+1] - $self->[0][$index+1]),
     };
}

sub EXISTS {
  my ($self, $index) = @_;

  $index >= 0 && $index < $#{$self->[0]}
    or return !1;

  return !0;
}

sub FETCHSIZE {
  my ($self) = @_;

  return @{$self->[0]} - 1;
}

package Squirrel::Template::Expr::WrapScalar::Match::Named;
use base 'Tie::Hash';

sub TIEHASH {
  my ($class, $nstarts, $nends) = @_;

  bless [ $nstarts, $nends ], $class;
}

sub FETCH {
  my ($self, $name) = @_;

  defined $self->[0]{$name}
    or return undef;

  return
    +{
      text => $self->[1]{$name},
     };
}

sub EXISTS {
  my ($self, $name) = @_;

  defined $self->[0]{$name}
    or return !1;

  return !0;
}

sub FIRSTKEY {
  my ($self) = @_;

  keys %{$self->[0]}; # reset

  each %{$self->[0]};
}

sub NEXTKEY {
  my ($self) = @_;

  each %{$self->[0]};
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

=item format(format)

Formats the scalar using a sprintf() format code.

  (10.123).format("%.2f") # "10.12"

=item escape(type)

Escape the scalar with the template defined escape method, eg. "html",
"uri".

  "a&b".escape("html") # "a&amp;b"

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

Replace the given C<regexp> in the string with C<replacement>.

If C<replacement> is a block, call the block with a match object (see
L</match(regexp)> below), and use the result as the replacement text.

If C<replacement> isn't a block it's treated as a string and C<$1> etc
are replaced with what the corresponding parenthesized expression in
the regexp matched.  C<$$> is replaced with C<$>.

If C<global> is present and true, replace every instance.

Does not modify the source, simply returns the modified text.

=item match(regexp)

Matches the string against C<regexp> returning undef on no match, or
returning a hash:

  {
    "start":start of whole match,
    "length":length of whole match,
    "end":end of whole match,
    "text":matching text of whole match,
    "subexpr": [
       {
         "start": start of first subexpr match,
         "length": length of first subexpr match,
         "end": end of first subexpr match,
         "text": matching text of first subexpr,
       },
       ...
    ],
    "named": {
      "name": {
        "text": matching text of named match,
      },
    }
  }

Note: C<subexpr> includes named matches.

=item substring(start)

=item substring(start, length)

Return the sub-string the scalar starting from C<start> for up to the
end of the string (or up to C<length> characters.)

Supports negative C<start> to count from the end of the end of the
string, and similarly for C<length>.

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
