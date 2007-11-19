package Squirrel::Row;
require 5.005;
use strict;

use Carp;
use BSE::DB;

my $dh = BSE::DB->single;

sub new {
  my ($class, @values) = @_;

  my @primary = $class->primary;
  my @columns = $class->columns;

  my $self = bless { }, $class;

  confess "Incorrect number of params supplied to ${class}::new, expected ",
    scalar(@columns)," but received ",scalar(@values)
      if @columns != @values;

  @$self{@columns} = @values;
  
  unless (defined $self->{$primary[0]}) {
    my $bases = $class->bases;
    if (keys %$bases) {
      my @bases = $class->_get_bases;
      my $base_base = $bases[0];
      my $base_class = $base_base->[1];
      my $sth = $dh->stmt("add$base_class")
	or confess "No add$base_class member in DatabaseHandle";

      # extract the base class columns
      my @base_cols = $base_class->columns;
      my %data;
      @data{$class->columns} = @values;
      $sth->execute(@data{@base_cols[1..$#base_cols]})
	or confess "Could not add $class/$base_class(undef, @data{@base_cols[1..$#base_cols]} )";
      my $primary_value = $dh->insert_id($sth);

      $self->{$primary[0]} = $primary_value;
      my $used_cols = @base_cols;

      # now do the derived classes and ourselves
      for my $derived (@bases) {
	my ($my_col, $base_class, $parent_class) = @$derived;

	$self->{$my_col} = $primary_value;

	my @cols = $parent_class->columns;
	splice(@cols, 0, $used_cols); # strip base column names
	$used_cols += @cols;

	$sth = $dh->stmt("add$parent_class")
	  or confess "No add$parent_class member in DatabaseHandle";
	$sth->execute(@$self{@cols})
	  or confess "Could not add $parent_class(@$self{@cols})";
      }
    }
    else {
      my $sth = $dh->stmt("add$class")
	or confess "No add$class member in DatabaseHandle";
      my $ret = $sth->execute(@values[1..$#values]);
      $ret && $ret != 0
	or confess "Could not add $class(undef, @values[1..$#values]) to database: ",$sth->errstr;
      $self->{$primary[0]} = $dh->insert_id($sth);
    }
  }

  confess "Undefined primary key fields in ${class}::new"
    if grep !defined, @$self{@primary};

  $self->{pkey} = join("", @$self{@primary});
  $self->{changed} = 0;

  $self;
}

sub foreign {
  return {};
}

sub primary {
  return qw(id);
}

sub bases {
  return {};
}

sub db_columns {
  my $class = shift;
  return $class->columns; # the same by default
}

sub save {
  my $self = shift;
  my %saved;
  my $bases = $self->bases;
  if (keys %$bases) {
    my @bases = $self->_get_bases;
    my $base_base = $bases[0];
    my $base_class = $base_base->[1];
    my $sth = $dh->stmt("replace$base_class")
      or confess "No replace$base_class member in DatabaseHandle";

    my @base_cols = $base_class->columns;
    $sth->execute(@$self{@base_cols})
      or confess "Cannot save $base_class part of ref $self:", $sth->errstr;
      
    # save the derived
    for my $derived (@bases) {
      my ($key_col, $base_class, $parent_class) = @$derived;

      my $base_cols = () = $base_class->columns;
      my @parent_cols = $parent_class->columns;
      splice(@parent_cols, 0, $base_cols);

      my $sth = $dh->stmt('replace'.$parent_class)
	or confess "No replace$parent_class statement available";
      $sth->execute(@$self{@parent_cols})
	or confess "Cannot save $parent_class part of ",ref $self,":",
	  $sth->errstr
    }
  }
  else {
    my $sth = $dh->stmt('replace'.ref $self)
      or confess "No replace",ref $self," member in DatabaseHandle";
    $sth->execute(@$self{$self->columns})
      or confess "Cannot save ",ref $self,":",$sth->errstr;
  }

  $self->{changed} = 0;
}

sub remove {
  my $self = shift;

  my $sth = $dh->stmt('delete'.ref($self));
  my $bases = $self->bases;
  my @primary = @$self{$self->primary};
  $sth->execute(@primary);
  while (keys %$bases) {
    my ($col) = keys %$bases;
    my $class = $bases->{$col}{class};
    my $sth = $dh->stmt('delete'.$class);
    $sth->execute(@primary);
    $bases = $class->bases;
  }

  # BUG: this should invalidate the cache
}

sub set {
  my ($self, $name, $value) = @_;

  exists $self->{$name}
    or do { warn "Attempt to set column '$name' in ",ref $self; return };
  $self->{$name} = $value;
  ++$self->{changed};

  return $value;
}

sub AUTOLOAD {
  use vars '$AUTOLOAD';
  (my $calledName = $AUTOLOAD) =~ s/^.*:://;
  for ($calledName) {
    /^set(.+)$/ && exists($_[0]->{lcfirst $1})
      && return $_[0]->set(lcfirst $1, $_[1]);
  }
  confess qq/Can't locate object method "$calledName" via package "/,
    ref $_[0],'"';
}

sub _get_bases {
  my ($class) = @_;

  # make sure we have a class name
  ref $class and $class = ref $class;

  my @bases;
  my $parent;
  my $base = $class;
  my $bases = $class->bases;
  while ($bases && keys %$bases) {
    keys %$bases == 1
      or confess "I don't know how to handle more than one base for $class";
    
    my ($my_col) = keys %$bases;
    $parent = $base;
    $base = $bases->{$my_col}{class};
    unshift @bases, [ $my_col, $base, $parent ];
    $bases = $base->bases;
  }

  @bases;
}

# in case someone tries AUTOLOAD tricks
sub DESTROY {
}

1;

__END__

=head1 NAME

  Squirrel::Row - base for rows

=head1 DESCRIPTION

A base class for implementing table row wrapper classes.

Based on code by Jason.

=head1 INTERFACE

=over 4

=item $row = Class->new(@values)

Class is some derived class.

Create a new object of that class.

=item $row->columns()

Return a list of column names in the table.  No default.

=item $row->foreign()

Returns a hashref for which the keys are column names and the values
are hashrefs with the following values:

=over 4

=item module

the table class

=item version

the minimum version number

=item null

the column allows NULL

=back

Returns an empty list by default.

The older code used column numbers, but was always looking up the
column name in the columns array, so it seemed a reasonable changed to
use the names instead.  It's also more stable against schema changes.
(And it saves me having to count columns.)

=item $row->primary()

Returns a list of the names of the columns that make up the primary key.

Defaults to ('id').

The older code returned column numbers, but was always looking up the
column names in the columns array.

=back

=NAME SEE ALSO

Squirrel::Table(3), perl(1)

=cut
