package Squirrel::Template::Expr::WrapHash;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.006";

sub _do_size {
  my ($self) = @_;

  return scalar keys %{$self->[0]};
}

sub _do_keys {
  my ($self) = @_;

  return [ keys %{$self->[0]} ];
}

sub _do_values {
  my ($self) = @_;

  return [ values %{$self->[0]} ];
}

sub _do_list {
  my ($self) = @_;

  my $item = $self->[0];
  return [ map +{ key => $_, value => $item->{$_} }, sort keys %$item ];
}

sub _do_delete {
  my ($self, $args) = @_;

  return delete @{$self->[0]}{@$args};
}

sub _do_set {
  my ($self, $args) = @_;

  @$args == 2
    or die [ error => "hash.set() requires 2 arguments" ];

  $self->[0]{$args->[0]} = $args->[1];

  return $args->[1];
}

sub _do_is_list {
  return 0;
}

sub _do_is_hash {
  return 1;
}

sub _do_is_code {
  return 0;
}

sub call {
  my ($self, $method, $args) = @_;

  my $real_method = "_do_$method";
  if ($self->can($real_method)) {
    return $self->$real_method($args);
  }
  elsif (exists $self->[0]{$method}) {
    my $item = $self->[0]{$method};
    if (ref $item 
	&& !Scalar::Util::blessed($item)
	&& Scalar::Util::reftype($item) eq 'CODE') {
      return $item->(@$args);
    }
    return $item;
  }
  else {
    return undef;
  }

  die [ error => "Unknown method $method for hashes" ];
}

1;

__END__

=head1 NAME

Squirrel::Template::Expr::WrapHash - virtual method wrapper for hashes

=head1 SYNOPSIS

  somehash.size
  somehash.keys
  somehash.values
  somehash.list
  somehash.delete(key)
  somehash.aKey
  somehash.set(key, value)
  somearray.is_list # always false
  somearray.is_hash # always true

=head1 DESCRIPTION

Provides virtual methods for hashes.

=head1 METHODS

=over

=item size

Return the numbers of keys in the hash.

=item keys

Return a list of the keys in the hash.

=item values

Return a list of the values in the hash.  The order of the elements of
the lists returned by keys and values correspond.

=item list

Return a list of hashes each containing a key and value containing the
key and value for each element of the hash.

=item delete

Delete a given key from the hash, returning the value that was at that
key.

=item set(key, value)

Set entry C<key> to C<value>.  Returns C<value>.

=item is_list

Test if this object is a list.  Always false for a hash.

=item is_hash

Test if this object is a hash.  Always true for a hash.

=item is_code

Test if this object is a code object.  Always false for a hash.

=back

=head1 SEE ALSO

L<Squirrel::Template::Expr>, L<Squirrel::Template>

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
