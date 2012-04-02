package Squirrel::Template::Expr::WrapArray;
use strict;
use base qw(Squirrel::Template::Expr::WrapBase);
use Scalar::Util ();

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

sub call {
  my ($self, $method, $args) = @_;

  my $real_method = "_do_$method";
  if ($self->can($real_method)) {
    return $self->$real_method($args);
  }
  die [ error => "Unknown method $method for lists" ];
}

1;
