package BSE::DB;
require 5.008;
use strict;
use Carp qw(croak);
use Carp qw/confess/;
use DBI::Const::GetInfoType;

our $VERSION = "1.003";

my $single;

my $constants_loaded = eval {
  require Constants;
  1;
};

sub cfg_entry {
  my ($class, $dbname, $key, $default) = @_;

  my $section = $dbname ? "db $dbname" : "db";

  return BSE::Cfg->single->entry($section, $key, $default);
}

sub dsn {
  my ($class, $dbname) = @_;

  return $class->cfg_entry($dbname, "dsn", $Constants::DSN);
}

sub dbuser {
  my ($class, $dbname) = @_;

  return $class->cfg_entry($dbname, "user", $Constants::UN);
}

sub dbpassword {
  my ($class, $dbname) = @_;

  return $class->cfg_entry($dbname, "password", $Constants::PW);
}

sub dbopts {
  my ($class, $dbname) = @_;

  my $def_opts = $Constants::DBOPTS || {};

  my $opts = $class->cfg_entry($dbname, "dbopts", $def_opts);
  unless (ref $opts) {
    my $work_opts = eval $opts;
    $@
      and confess "Error evaluation db options: $@";

    $opts = $work_opts;
  }

  return $opts;
}

sub init {
  my ($class, $cfg) = @_;

  $single and return;

  my $dbclass = $class->cfg_entry(undef, "class", "BSE::DB::Mysql");
  
  my $file = $dbclass;
  $file =~ s!::!/!g;
  require "$file.pm";

  $single = $dbclass->_single($cfg);
}

sub new_dbh {
  my ($self, $dbname) = @_;

  my $dbclass = $self->cfg_entry($dbname, "class", "BSE::DB::Mysql");

  my $file = $dbclass;
  $file =~ s!::!/!g;
  require "$file.pm";

  return $dbclass->connect($dbname);
}

sub single {
  $single
    or confess "BSE::DB->init(\$cfg) needs to be called first";
  $single;
}

sub startup {
  $single->_startup();
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

  my $result = $sth->execute(@args)
    or confess "Cannot execute statement $name: ",$sth->errstr;

  return 0 + $result;
}

sub dbh {
  $_[0]{dbh};
}

sub id_quote {
  my $self = shift;

  unless (defined $self->{id_quote}) {
    $self->{id_quote} = $self->dbh->get_info($GetInfoType{SQL_IDENTIFIER_QUOTE_CHAR});
    defined $self->{id_quote} or $self->{id_quote} = "";
  }

  return $self->{id_quote};
}

sub quote_id {
  my ($self, $id) = @_;

  my $q = $self->id_quote;

  return $q . $id . $q;
}

sub forked {
  my $self = shift;

  $self = BSE::DB->single unless ref $self;

  $self->_forked;
}

sub _query_expr {
  my ($args, $map, $table_name, $op, @terms) = @_;

  if (lc $op eq 'and' || lc $op eq 'or') {
    return '(' . join (" $op ", map _query_expr($args, $map, $table_name, @$_), @terms) . ')';
  }
  else {
    my ($column, @values) = @terms;
    my $db_col = $map->{$column}
      or confess "No column '$column' in $table_name";
    if ($op eq "between") {
      push @$args, @values[0, 1];
      return "$db_col $op ? and ?";
    }
    else {
      push @$args, $values[0];
      return "$db_col $op ?";
    }
  }
}

sub generate_query {
  my ($self, $row_class, $columns, $query, $opts) = @_;

  my %trans;
  @trans{$row_class->columns} = $row_class->db_columns;

  my $table_name = $row_class->table;

  my @out_columns = map 
    {; $trans{$_} or confess "No column '$_' in $table_name" } @$columns;
  my $sql = 'select ' . join(',', @out_columns) . ' from ' . $table_name;
  my @args;
  if ($query && @$query) {
    $sql .= ' where ' . _query_expr(\@args, \%trans, $table_name, 'and', @$query,);
  }
  if ($opts->{order}) {
    $sql .= "order by " . $opts->{order};
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

sub insert_stmt {
  my ($self, $table_name, $columns) = @_;

  my $dbh = $self->dbh;
  my @columns = map $dbh->quote_identifier($_), @$columns;
  my $sql = "insert into $table_name(" . join(",", @columns) . ")";
  $sql .= " values(" . join(",", ("?") x @$columns) . ")";

  my $sth = $self->{dbh}->prepare($sql);
  $sth
    or confess "Cannot prepare generated sql $sql: ", $self->{dbh}->errstr;

  return $sth;
}

sub update_stmt {
  my ($self, $table_name, $pkey, $cols) = @_;

  my @cols = map $self->quote_id($_), @$cols;
  my $sql = "update $table_name set\n  " .
    join(",\n  ", map "$_ = ?", @cols) .
      "\n  where $pkey = ?";

  my $sth = $self->{dbh}->prepare($sql);
  $sth
    or confess "Cannot prepare generated sql $sql: ", $self->{dbh}->errstr;

  return $sth;
}

sub delete_stmt {
  my ($self, $table_name, $pkeys) = @_;

  my @where = map "$_ = ?", @$pkeys;
  my $sql = "delete from $table_name where " . join " and ", @where;

  my $sth = $self->{dbh}->prepare($sql);
  $sth
    or confess "Cannot prepare generated sql $sql: ", $self->{dbh}->errstr;

  return $sth;
}

sub auto_commit {
  my ($self, $value) = @_;

  $self = BSE::DB->single unless ref $self;
  $self->dbh->{AutoCommit} = $value;
}

sub begin_work {
  my ($self) = @_;

  $self = BSE::DB->single unless ref $self;

  $self->dbh->begin_work;
}

sub commit {
  my ($self) = @_;

  $self = BSE::DB->single unless ref $self;

  $self->dbh->commit;
}

sub rollback {
  my ($self, $value) = @_;

  $self = BSE::DB->single unless ref $self;

  $self->dbh->rollback;
}

sub do_txn {
  my ($self, $code) = @_;

  eval {
    $self->begin_work;
    $code->();
    $self->commit;
    1;
  } or do {
    my $error = $@;

    $self->rollback;
    $self->auto_commit(1);
    die $error;
  };

  return 1;
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
