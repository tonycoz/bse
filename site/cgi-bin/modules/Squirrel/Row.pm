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
      keys %$bases == 1
	or confess "I don't know how to handle more than one base for $class";
      my ($my_col) = keys %$bases;
      my $base_class = $bases->{$my_col}{class};
      my $sth = $dh->stmt("add$base_class")
	or confess "No add$base_class member in DatabaseHandle";
      
      # extract the base class columns
      my @base_cols = $base_class->columns;
      my %data;
      @data{$class->columns} = @values;
      $sth->execute(@data{@base_cols[1..$#base_cols]})
	or confess "Could not add $class/$base_class(undef, @data{@base_cols[1..$#base_cols]} )";
      $self->{$primary[0]} = $self->{$my_col} =
	$data{$my_col} = $data{$primary[0]} = $dh->insert_id($sth);
      
      # now do this class
      # what do we store
      my %saved;
      @saved{@base_cols} = @base_cols;
      delete $saved{$my_col}; # make sure we save this
      my @save_cols = grep !$saved{$_}, @columns;
      $sth = $dh->stmt("add$class")
	or confess "No add$class member in DatabaseHandle";
      $sth->execute(@data{@save_cols})
	or confess "Could not add $class(@data{1..$#save_cols})";
    }
    else {
      my $sth = $dh->stmt("add$class")
	or confess "No add$class member in DatabaseHandle";
      my $ret = $sth->execute(@values[1..$#values]);
      $ret != 0
	or confess "Could not add $class(undef, @values[1..$#values]) to database: ",$sth->errstr;
      $self->{$primary[0]} = $dh->insert_id($sth);
    }
  }

  confess "Undefined primary key fields in ${class}::new"
    if grep !defined, @$self{@primary};

  my $foreign = $self->foreign;
  for my $key (keys %$foreign) {
    my $module = $foreign->{$key}{module};
    my $version = $foreign->{$key}{version};

    next unless defined $module;

    next if !defined($self->{$key}) && exists $foreign->{$key}{null};

    require $module.'.pm';

    $module->VERSION($version) if defined $version;

    my $mod = $module->new;

    confess "Bad FK field $class($key) ($self->{$key})"
	unless $self->{$key} = $mod->getByPkey($self->{$key});
  }

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

sub save {
  my $self = shift;
  my %saved;
  my $bases = $self->bases;
  if (keys %$bases) {
    # save to the bases
    # this should probably recurse at some point
    for my $base_key (keys %$bases) {
      # we have bases, update them
      my $base_class = $bases->{$base_key}{class};
      my @base_cols = $base_class->columns;
      my $sth = $dh->stmt('replace'.$base_class)
	or confess "No replace$base_class member in DatabaseHandle";
      my @data;
      for my $col (@base_cols) {
	push(@data, ref $self->{$col} ? $self->{$col}{pkey} : $self->{$col});
	++$saved{$col};
      }
      $sth->execute(@data)
	or confess "Cannot save $base_class part of ",ref $self,":",
	  $sth->errstr;
    }
  }

  my $sth = $dh->stmt('replace'.ref $self)
    or confess "No replace",ref $self," member in DatabaseHandle";
  my @data;
  for my $col ($self->columns) {
    push(@data, ref $self->{$col} ? $self->{$col}{pkey} : $self->{$col})
      unless $saved{$col};
  }
  $sth->execute(@data)
    or confess "Cannot save ",ref $self,":",$sth->errstr;

  $self->{changed} = 0;
}

sub remove {
  my $self = shift;
  my $sth = $dh->stmt('delete'.ref($self));
  $sth->execute(@$self{$self->primary});

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
