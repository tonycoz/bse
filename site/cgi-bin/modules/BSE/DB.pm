package BSE::DB;
require 5.005;
use strict;
use Carp qw(croak);
use Carp qw/confess/;

use vars qw($VERSION);
$VERSION = '1.00';

use Constants qw/$DBCLASS/;

my $file = $DBCLASS;
$file =~ s!::!/!g;
require "$file.pm";

sub single {
  $DBCLASS->_single();
}

sub startup {
  $DBCLASS->_startup();
}

sub query {
  my ($self, $name, @args) = @_;

  $self = BSE::DB->single unless ref $self;

  my $sth = $self->stmt($name);

  $sth->execute(@args)
    or croak "Cannot execute statement $name: ",$sth->errstr;
  my @results;
  while (my $row = $sth->fetchrow_hashref) {
    push(@results, { %$row } );
  }
  return @results;
}

sub run {
  my ($self, $name, @args) = @_;

  $self = BSE::DB->single unless ref $self;

  my $sth = $self->stmt($name);

  $sth->execute(@args)
    or confess "Cannot execute statement $name: ",$sth->errstr;
}

sub dbh {
  $_[0]{dbh};
}

sub _query_expr {
  my ($args, $map, $table_name, $op, @terms) = @_;

  if (lc $op eq 'and' || lc $op eq 'or') {
    return '(' . join (" $op ", map _query_expr($args, $map, $table_name, @$_), @terms) . ')';
  }
  else {
    my ($column, $value) = @terms;
    my $db_col = $map->{$column}
      or confess "No column '$column' in $table_name";
    push @$args, $value;
    return "$db_col $op ?";
  }
}

sub generate_query {
  my ($self, $table, $columns, $query) = @_;

  my $row_class = $table->rowClass;
  my %trans;
  @trans{$row_class->columns} = $row_class->db_columns;

  my $table_name = $table->table;

  my @out_columns = map 
    {; $trans{$_} or confess "No column '$_' in $table_name" } @$columns;
  my $sql = 'select ' . join(',', @out_columns) . ' from ' . $table_name;
  my @args;
  if ($query) {
    $sql .= ' where ' . _query_expr(\@args, \%trans, $table_name, 'and', @$query,);
  }

  #print STDERR "generated sql >$sql<\n";
  my $sth = $self->{dbh}->prepare($sql)
    or confess "Cannot prepare >$sql<: ", $self->{dbh}->errstr;
  $sth->execute(@args)
    or confess "Cannot execute >$sql< @args : ", $sth->errstr;
  my @rows;
  while (my $row = $sth->fetchrow_arrayref) {
    my %row;
    @row{@$columns} = @$row;
    push @rows, \%row;
  }

  return @rows;
}

1;

__END__

=head1 NAME

  BSE::DB - a wrapper class used by BSE to give a common interface to several databases

=head1 SYNOPSIS

  my $dh = BSE::DB->single;
  my $sth = $dh->stmt($stmt_name);
  $sth->execute() or die;
  my $id = $dh->insert_id($sth)

=head1 DESCRIPTION

BSE::DB->single() returns a wrapper object defined by the class
specified by $DBCLASS.

Currently only the following methods are defined:

=over

=item stmt($name)

Returns a statement based on the given name.

=item insert_id($sth)

After a statement is executed that inserts into a table that has an
auto defining key, eg. auto_increment on mysql or identity on T-SQL
databases.  This method returns the value of the inserted key.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

bse.pod

=cut
