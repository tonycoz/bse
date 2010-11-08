package Squirrel::Row;
require 5.005;
use strict;

our $VERSION = "1.000";

use Carp;
use BSE::DB;

my %methods_created;

my $dh;

sub new {
  my ($class, @values) = @_;

  $methods_created{$class}
    or $class->_create_methods();

  my @primary = $class->primary;
  my @columns = $class->columns;

  my $self = bless { }, $class;

  confess "Incorrect number of params supplied to ${class}::new, expected ",
    scalar(@columns)," but received ",scalar(@values)
      if @columns != @values;

  @$self{@columns} = @values;
  
  $dh ||= BSE::DB->single;
  unless (defined $self->{$primary[0]}) {
    my $bases = $class->bases;
    if (keys %$bases) {
      my @bases = $class->_get_bases;
      my $base_base = $bases[0];
      my $base_class = $base_base->[1];

      my $sth = $dh->stmt("add$base_class");

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
      my $sth = $dh->stmt_noerror("add$class");
      my @cols = $self->db_columns;
      shift @cols; # lose the pkey
      $sth ||= $dh->insert_stmt($self->table, \@cols)
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

sub defaults {
  return;
}

sub db_columns {
  my $class = shift;
  return $class->columns; # the same by default
}

sub save {
  my $self = shift;
  my %saved;
  my $bases = $self->bases;
  $dh ||= BSE::DB->single;
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
    my $member = 'replace'.ref $self;
    my @exe_vals = @$self{$self->columns};
    my $sth = $dh->stmt_noerror($member);
    unless ($sth) {
      my ($pkey_col) = $self->primary;
      my @nonkey = grep $_ ne $pkey_col, $self->columns;
      @exe_vals = @$self{@nonkey, $pkey_col};
      $member = 'update'.ref $self;
      $sth = $dh->stmt_noerror($member);

      unless ($sth) {
	# not strictly correct, but plenty of other code makes the
	# same assumption
	my @db_cols = $self->db_columns;
	$pkey_col = shift @db_cols;
	$sth = $dh->update_stmt($self->table, $pkey_col, \@db_cols);
      }
    }
    $sth
      or confess "No replace",ref $self," member in DatabaseHandle";
    $sth->execute(@exe_vals)
      or confess "Cannot save ",ref $self,":",$sth->errstr;
  }

  $self->{changed} = 0;
}

sub remove {
  my $self = shift;

  $dh ||= BSE::DB->single;
  my $bases = $self->bases;
  my @primary = @$self{$self->primary};
  if (keys %$bases) {
    my $sth = $dh->stmt('delete'.ref($self));
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
  else {
    my $member = 'delete'.ref($self);
    my $sth = $dh->stmt_noerror($member);
    unless ($sth) {
      $sth = $dh->delete_stmt($self->table, [ $self->primary ]);
    }
    $sth
      or confess "No $member member in DatabaseHandle";
    $sth->execute(@primary)
      or confess "Cannot delete ", ref $self, ":", $sth->errstr;
  }
}

sub set {
  my ($self, $name, $value) = @_;

  exists $self->{$name}
    or do { warn "Attempt to set column '$name' in ",ref $self; return };
  $self->{$name} = $value;
  ++$self->{changed};

  return $value;
}

use vars '$AUTOLOAD';

sub AUTOLOAD {
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

sub data_only {
  my ($self) = @_;

  my %result;
  my @cols = $self->columns;
  @result{@cols} = @{$self}{@cols};

  return \%result;
}

# in case someone tries AUTOLOAD tricks
sub DESTROY {
}

sub _create_methods {
  my $class = shift;

  $methods_created{$class} = 1;

  my $bases = $class->bases;
  my @bases = map $_->{class}, values %$bases;
  my %all_cols = map { $_ => 1 } $class->columns;
  for my $base (@bases) {
    unless ($methods_created{$base}) {
      $base->_create_methods();
    }
    delete @all_cols{$base->columns};
  }
  for my $col (keys %all_cols) {
    unless ($class->can("set_$col")) {
      no strict 'refs';
      my $work_col = $col; # for closure
      *{"${class}::set_$col"} = sub { $_[0]{$work_col} = $_[1] };
    }
    unless ($class->can($col)) {
      no strict 'refs';
      my $work_col = $col; # for closure
      *{"${class}::$col"} = sub { $_[0]{$work_col} };
    }
  }
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

Preferably, use the make method of the table class, See
Squirrel::Table.

=item $row->save

Save the row to the database.

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

=item $row->db_columns

Columns as they are named in the database.  Defaults to calling columns().

=item $row->remove

Remove the row from the database.

=item Class->defaults

Returns defaults as name, value pairs suitable for assignment to hash.
Used by make() in Squirrel::Table.

=item $row->data_only

Returns the data of the row as a hashref, with no extra housekeeping
data.

=back

=NAME SEE ALSO

Squirrel::Table(3), perl(1)

=cut
