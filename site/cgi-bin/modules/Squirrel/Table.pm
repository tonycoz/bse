package Squirrel::Table;

use vars qw($VERSION);
use Carp;
use strict;

$VERSION = 0.1;

use BSE::DB;

my $dh = BSE::DB->single;

# no caching is performed if this is zero
my $cache_timeout = 2; # seconds

# cache of loaded tables
# this prevents us from reloading the table so often
# key is the table class name, value is a hash ref with two keys:
#  table - the table object
#  when - time value when the object was created.
# Table::add() invalidates the cache for the given class
my %cache;

sub new {
  my ($class, $nocache) = @_;

  return $cache{$class}{table}
    if !$nocache
      && exists $cache{$class} 
      && defined $cache{$class}{time}
      && $cache{$class}{time}+$cache_timeout >= time;

  my $sth = $dh->stmt($class)
    or confess "No $class member in DatabaseHandle";
  $sth->execute
    or confess "Cannot execute $class handle from DatabaseHandle:",DBI->errstr;

  my %coll;
  my @order;
  my $rowClass = $class->rowClass;
  require $rowClass.".pm";
  while (my $row = $sth->fetchrow_arrayref) {
    my $item = $rowClass->new(@$row);
    $coll{$item->{pkey}} = $item;
    push(@order, $item);
    
  }

  my $result = bless { ptr=>-1, coll=>\%coll, order=>\@order }, $class;

  if ($cache_timeout) {
    $cache{$class}{table} = $result;
    $cache{$class}{when} = time;
  }

  return $result;
}

sub EOF {
  my $self = shift;

  ++$self->{ptr} >= @{$self->{order}};
}

sub getNext {
  my $self = shift;
  return $self->{order}[$self->{ptr}];
}

sub getByPkey {
  my ($self, @values) = @_;
  if (ref($self)) {
    return $self->{coll}{join "", @values};
  }
  else {
    # try to get row by key
    my $rowClass = $self->rowClass;
    require $rowClass . ".pm";
    my $member = "get${rowClass}ByPkey";
    my $sth = $dh->stmt($member)
      or confess "No $member in DatabaseHandle";
    $sth->execute(@values)
      or confess "Cannot execute $member handle from DatabaseHandle:", DBI->errstr;
    # should only be one row
    if (my $row = $sth->fetchrow_arrayref) {
      return $rowClass->new(@$row);
    }
    else {
      return undef;
    }
  }
}

sub add {
  my ($self, @data) = @_;

  require $self->rowClass.".pm";
  my $item = $self->rowClass->new(undef, @data);

  # if called as an instance method
  if (ref($self)) {
    delete $cache{ref $self};
    $self->{coll}{$item->{pkey}} = $item;
    push(@{$self->{order}}, $item);
  }
  else {
    delete $cache{ref $self};
  }

  return $item;
}

# get all values in a particular column
sub getAll {
  my ($self, $column) = @_;
  my @values = map { $_->{$column} } @{$self->{order}};

  return wantarray ? @values : \@values;
}

# column grep
sub getBy {
  my ($self, $column, $value) = @_;

  my @results;
  if (ref($self) && UNIVERSAL::isa($self, __PACKAGE__)) {
    # this is an object with the rows already loaded
    for my $row (@{$self->{order}}) {
      my $comp = ref $row->{$column} ? $row->{$column}->getPkey : $row->{$column};
      push @results, $row if $comp eq $value;
    }
  }
  else {
    # ask the database directly
    my $rowClass = $self->rowClass;
    require $rowClass . ".pm";
    my $member = "get${rowClass}By\u$column";
    my $sth = $dh->stmt($member)
      or confess "No $member in BSE::DB";
    $sth->execute($value)
      or confess "Cannot execute $member from BSE::DB: ",DBI->errstr;
    while (my $row = $sth->fetchrow_arrayref) {
      push(@results, $rowClass->new(@$row));
    }
  }

  return wantarray ? @results : $results[0];
}

sub getSpecial {
  my ($self, $name, @args) = @_;

  unless (ref $self) {
    $self = $self->new(preload=>0);
  }
  my $rowClass = $self->rowClass;
  my $sqlname = ref($self) . "." . $name;
  my $sth = $dh->stmt($sqlname)
    or confess "No $sqlname in database object";
  $sth->execute(@args)
    or confess "Cannot execute $sqlname: ", $sth->errstr;
  my @results;
  while (my $row = $sth->fetchrow_arrayref) {
    push(@results, $rowClass->new(@$row));
  }

  wantarray ? @results : \@results;
}

# a list of all rows in select order
sub all {
  my $self = shift;

  unless (ref $self) {
    $self = $self->new();
  }

  return @{$self->{order}};
}

1;

__END__

=head1 NAME

Base class for tables.

=head1 DESCRIPTION

This needs more documentation.

=head1 IMPLEMENT IN THE BASE

=over 4

=item rowClass()

Returns the name of the class implementing the rows for this class.

=back

=head1 IMPLEMENT IN DatabaseHandle

=head1 METHODS

Some methods can be used as both class and instance methods.

In these cases when used as a class method they ask the database
directly for the information.  This requires that appropriate keys be
defined in the DatabaseHandle object.

In the examples SomeTable is used as the name of the table class
derived from Squirell::Table.

=over 4

=item $table = SomeTable->new

Loads the contents of the table into memory.

=item until ($table->EOF) { ... }

Bumps the index into the table, returns TRUE if we've passed the end
of the table.

=item $row = $table->getNext

Gets the currently indexed item in the table.

=item $row = $table->getByPkey(@values)

=item $row = SomeTable->getByPkey(@values)

Retrieves the specified row from the database.

For the class method version to work you must have a statement handle
in the DatabaseHandle object called get${rowClass}ByPkey.

=item $row = $table->add(@data)

=item $row = SomeTable->add(@data)

Adds a row to the table.  @data must contain all except the primary key.

=item @rows = $table->getAll($column)

Returns a list containing that column for each row in the table.

Returns an array ref if called in a scalar context.

=item @rows = $table->getBy($column, $value)

=item @rows = SomeTable->getBy($column, $value)

Returns any rows where the given column has that value.

Returns the first element of the list if called in scalar context
(though it still retrieves the whole lot.)

For the class method form to work the DatabaseHandle object must have
a member "get${rowClass}By\u$column".

=back

=cut

