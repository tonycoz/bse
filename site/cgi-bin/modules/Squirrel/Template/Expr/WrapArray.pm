package Squirrel::Template::Expr::WrapArray;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);
use Scalar::Util ();

our $VERSION = "1.003";

my $list_make_key = sub {
  my ($item, $field) = @_;

  if (Scalar::Util::blessed($item)) {
    return $item->can($field) ? $item->$field() : "";
  }
  else {
    return exists $item->{$field} ? $item->{$field} : "";
  }
};

sub _do_size {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.size takes no parameters" ];

  return scalar @{$self->[0]};
}

sub _do_sort {
  my ($self, $args) = @_;

  @{$self->[0]} <= 1
    and return [ @{$self->[0]} ]; # nothing to sort

  if (@$args == 0) {
    return [ sort @{$self->[0]} ];
  }
  elsif (@$args == 1) {
    my $key = $args->[0];
    return 
      [
       sort {
	 $list_make_key->($a, $key) cmp $list_make_key->($b, $key)
       } @{$self->[0]}
      ];
  }
  else {
    die [ error => "list.sort takes 0 or 1 parameters" ];
  }
}

sub _do_reverse {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.reverse takes no parameters" ];

  return [ reverse @{$self->[0]} ];
}

sub _do_join {
  my ($self, $args) = @_;

  my $join = @$args ? $args->[0] : "";

  return join($join, @{$self->[0]});
}

sub _do_last {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.last takes no parameters" ];

  return @{$self->[0]} ? $self->[0][-1] : ();
}

sub _do_first {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.first takes no parameters" ];

  return @{$self->[0]} ? $self->[0][0] : ();
}

sub _do_shift {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.shift takes no parameters" ];

  return shift @{$self->[0]};
}

sub _do_pop {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.pop takes no parameters" ];

  return pop @{$self->[0]};
}

sub _do_push {
  my ($self, $args) = @_;

  push @{$self->[0]}, @$args;

  return scalar(@{$self->[0]});
}

sub _do_unshift {
  my ($self, $args) = @_;

  unshift @{$self->[0]}, @$args;

  return scalar(@{$self->[0]});
}

sub _do_expand {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.expand takes no parameters" ];

  return 
    [ map {
      defined 
	&& ref
	  && !Scalar::Util::blessed($_)
	    && Scalar::Util::reftype($_) eq 'ARRAY'
	      ? @$_
		: $_
    } @{$self->[0]} ];
}

sub _do_is_list {
  return 1;
}

sub _do_is_hash {
  return 0;
}

sub call {
  my ($self, $method, $args) = @_;

  my $real_method = "_do_$method";
  if ($self->can($real_method)) {
    return $self->$real_method($args);
  }
  die [ error => "Unknown method $method for lists" ];
}

1;

__END__

=head1 NAME

Squirrel::Template::Expr::WrapArray - provide virtual methods for arrays

=head1 SYNOPSIS

  somearray.size
  sorted = somearray.sort()
  sorted = somearray.sort(key)
  reversed = somearray.reverse
  joined = somearray.join()
  joined = somearray.join(":")
  last = somearray.last
  first = somearray.first
  first = somearray.shift # modifies somearray
  somearray.push(avalue);
  last = somearray.pop # modifies somearray
  somearray.unshift(avalue);
  somearray.is_list # always true
  somearray.is_hash # always false

=head1 DESCRIPTION

This class provides virtual methods for arrays (well, array
references) in L<Squirrel::Template>'s expression language.

=head1 METHODS

=over

=item size

The number of elements in the list.

=item sorted()

The elements sorted by name.

=item sorted(fieldname)

The elements sorted as objects calling C<fieldname>.

=item reversed

The elements in reverse order.

=item join()

A string with the elements concatenated together.

=item join(sep)

A string with the elements concatenated together, separated by C<sep>.

=item last

The last element in the array, or undef.

=item first

The first element in the array, or undef.

=item shift

Remove the first element from the list and return that.

=item push(element,...)

Add the given elements to the end of the array.  returns the new size
of the array.

=item pop

Remove the last element from the list and return that.

=item unshift(element,...)

Add the given elements to the start of the array.  returns the new
size of the array.

=item expand

Return a new array with any contained arrays expanded one level.

  [ [ [ 1 ], 2 ], 3 ].expand => [ [ 1 ], 2, 3 ]

=item is_list

Test if this object is a list.  Always true for a list.

=item is_hash

Test if this object is a hash.  Always false for a list.

=back

=head1 SEE ALSO

L<Squirrel::Template::Expr>, L<Squirrel::Template>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
