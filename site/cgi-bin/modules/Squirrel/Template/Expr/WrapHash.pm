package Squirrel::Template::Expr::WrapHash;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);

our $VERSION = "1.002";

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
  return [ map {; key => $_, value => $item->{$_} } sort keys %$item ];
}

sub _do_delete {
  my ($self, $args) = @_;

  return delete @{$self->[0]}{@$args};
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

  my $wrapper = Squirrel::Template::Expr::WrapHash->new(\%somehash);

  <:= somehash.size :>
  <:= somehash.keys :>
  <:= somehash.values :>
  <:= somehash.list :>
  <:= somehash.delete(key) :>
  <:= somehash.aKey :>

=head1 DESCRIPTION

Provides virtual methods for hashes.

=cut
