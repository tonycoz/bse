package Squirrel::Template::Expr::WrapArray;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);
use Scalar::Util ();
use List::Util ();

our $VERSION = "1.011";

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
    if (ref $args->[0]) {
      my $eval = $self->expreval;
      return
	[
	 sort {
	   $eval->call_function($args->[0], [ $a, $b ])
	 } @{$self->[0]}
	];
    }
    else {
      my $key = $args->[0];
      return 
	[
	 sort {
	   $list_make_key->($a, $key) cmp $list_make_key->($b, $key)
	 } @{$self->[0]}
	];
    }
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

sub _do_shuffle {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.shuffle takes no parameters" ];

  return [ List::Util::shuffle(@{$self->[0]}) ];
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

sub _do_is_code {
  return 0;
}

sub _do_defined {
  return 1;
}

sub _do_set {
  my ($self, $args) = @_;

  @$args == 2
    or die [ error => "list.set takes two parameters" ];

  $self->[0][$args->[0]] = $args->[1];

  return $args->[1];
}

sub _do_as_hash {
  my ($self, $args) = @_;

  @$args == 0
    or die [ error => "list.as_hash takes no parameters" ];

  my @extra = @{$self->[0]} % 2 ? ( undef ) : ();

  return +{ @{$self->[0]}, @extra };
}

sub _do_grep {
  my ($self, $args) = @_;

  my $eval = $self->expreval;
  return
    [
     grep $eval->call_function($args->[0], [ $_ ]),
     @{$self->[0]}
    ];
}

sub _do_map {
  my ($self, $args) = @_;

  my $eval = $self->expreval;
  return
    [
     map $eval->call_function($args->[0], [ $_ ]),
     @{$self->[0]}
    ];
}

sub _do_maphash {
  my ($self, $args) = @_;

   @$args <= 2
     or die [ error => "list.maphash requires 0 to 2 parameters" ];

  if (@$args) {
    my $id = $args->[0];
    my $value = @$args > 1 ? $args->[1] : undef;

    my $eval = $self->expreval;
    if (ref $id) {
      if (defined $value) {
	if (ref $value) {
	  return +{
		   map {
		     scalar($eval->call_function($id, [ $_ ])) =>
		       scalar($eval->call_function($value, [ $_ ]))
		     } @{$self->[0]}
		  };
	}
	else {
	  return +{
		   map {
		     scalar($eval->call_function($id), [ $_ ]) =>
		       scalar($list_make_key->($_, $value))
		     } @{$self->[0]}
		  };
	}
      }
      else {
	return +{
		 map {
		   scalar($eval->call_function($id), [ $_ ]) => $_
		 } @{$self->[0]}
		};
      }
    }
    else {
      if (defined $value) {
	if (ref $value) {
	  return +{
		   map {
		     scalar($list_make_key->($_, $id)) =>
		       scalar($eval->call_function($value, [ $_ ]))
		     } @{$self->[0]}
		  };
	}
	else {
	  return +{
		   map {
		     scalar($list_make_key->($_, $id)) =>
		       scalar($list_make_key->($_, $value))
		     } @{$self->[0]}
		  };
	}
      }
      else {
	return +{
		 map {
		   scalar($list_make_key->($_, $id)) => $_
		 } @{$self->[0]}
		};
      }
    }
  }
  else {
    return +{ map {$_ => 1} @{$self->[0]} };
  }
}

sub _do_slice {
  my ($self, $args) = @_;

  my @result;
  if (@$args == 1 && Scalar::Util::reftype($args->[0]) eq "ARRAY") {
    @result = @{$self->[0]}[@{$args->[0]}];
  }
  else {
    @result = @{$self->[0]}[@$args];
  }

  return \@result;
}

sub _do_splice {
  my ($self, $args) = @_;

  @$args >= 1 && @$args <= 3
    or die [ error => "list.splice() requires 1 to 3 parameters" ];
  my $offset = $args->[0];
  $offset < 0 and $offset = @{$self->[0]} + $offset;
  my $len = @$args >= 2 ? $args->[1] : @{$self->[0]} - $offset;
  my $replace = [];
  if (@$args >= 3) {
    Scalar::Util::reftype($args->[2]) eq "ARRAY"
      or die [ error => "list.splice() third argument must be a list" ];
    $replace = $args->[2];
  }

  return [ splice(@{$self->[0]}, $offset, $len, @$replace) ];
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
  somearray.push(avalue)
  last = somearray.pop # modifies somearray
  somearray.unshift(avalue)
  somearray.is_list # always true
  somearray.is_hash # always false
  odd = somearray.grep(@{a: a mod 2 == 0 })
  doubled = somearray.map(@{a: a * 2 })

=head1 DESCRIPTION

This class provides virtual methods for arrays (well, array
references) in L<Squirrel::Template>'s expression language.

=head1 METHODS

=over

=item size

The number of elements in the list.

=item sort()

The elements sorted by name.

=item sort(fieldname)

The elements sorted as objects calling C<fieldname>.

=item sort(block)

The elem

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

=item grep(block)

Return a new list containing only those elements that C<block> returns
true for.

=item map(block)

Return the list of return values from C<block> as applied to each
element.

=item set(index, value)

Set the specified I<index> in the array to I<value>.  Returns
I<value>.

=item splice(array_of_indexes)

=item splice(index1, index2, ...)

Return a selection of elements from the array as a new array specified
by index.  The indexes can be supplied either as an array:

  [ "A" .. "Z" ].slice([ 0 .. 5 ]) # first 6 elements

or as separate arguments:

  [ "A" .. "Z" ].slice(0, 1, -2, -1) # first 2 and last 2 elements

=item splice(start)

=item splice(start, count)

=item splice(start, count, replace)

Removes elements from an array, optionally inserting the elements in
the I<replace> aray in their place.

If I<count> is ommitted, all elements to the end of the array are
removed.

If I<replace> is omitted, the elements are simply removed.

  <: .set foo = [ "A" .. "J" ] :>
  <:= foo.splice(5).join("") :> # FGHIJ
  <:= foo.join("") :>           # ABCDE since splice() modifies it's argument
  <: .set bar = [ "A" .. "J" ] :>
  <:= bar.splice(8, 2, [ "Y", "Z" ]).join("") :> # IJ
  <:= bar.join("") :> # ABCDEFGHYZ

=item as_hash

Returns a hash formed as if the array was formed of key and value
pairs.  If the number of elements is odd, the value for the odd key is
C<undef>.

 [ "a", 1, "b", 2 ].as_hash => { a:1, b:2 }

=item maphash

Returns a new hash with each item from the array as a key, and all values of 1.

This simiplifies turning a list of strings into an existence checking hash.

  <:.set strs = [ "one", "two", "three" ] :>
  <:.set strhash = strs.maphash :>
  <:= strhash.exists("one") :>   # 1
  <:= strhash.exists("four") :>  # (empty string)

=item maphash(key)

=item maphash(key, value)

Returns a new hash with the key and values derived from the elements
of the list.

Each I<key> and I<value> can be either an element name, treating the
array elements as hashes/objects, or a block.

If I<value> isn't supplied then the element from the array is used.

  <:.set objs = [ { id: 1, firstn: "Tony", lastn: "Cook", note: "Programming Geek" },
                  { id: 2, firstn: "Adrian", lastn: "Oldham", note: "Design Geek" } ] :>
  <:.set byid = objs.maphash("id") :>
  <:= byid[2].firstn :>   # Adrian
  <:.set byname = objs.maphash(@{i: i.firstn _ " " _ i.lastn }) :>
  <:= byname["Tony Cook"].note :>  # Programming Geek
  <:=.set namebynote = objs.maphash(@{i: i.note.lower }, @{i: i.firstn _ " " _ i.lastn }) :>
  <:= namebynote["design geek"] :>  # Adrian Oldham

=item is_list

Test if this object is a list.  Always true for a list.

=item is_hash

Test if this object is a hash.  Always false for a list.

=item is_code

Test if this object is a code object.  Always false for a list.

=item defined

Always true for arrays.

=back

=head1 SEE ALSO

L<Squirrel::Template::Expr>, L<Squirrel::Template>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
