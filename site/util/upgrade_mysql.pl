#!perl -w
use strict;
use lib '../cgi-bin/modules';
use DBI;
use BSE::DB;
use Getopt::Long;

my $verbose;
my $pretend;
my $didbackup;

Getopt::Long::Configure('bundling');
GetOptions("v:i", \$verbose,
	   "n", \$pretend,
	   "b", \$didbackup);
$verbose = 1 if defined $verbose && $verbose == 0;

if ($didbackup) {
  print "Since you gave the -b option, I assume you made a backup.\n";
}
else {
  my $conf = int(rand(1000))+1;
  print <<EOS;
This tool attempts to add missing tables, columns and indices to your
database.

It's possible it will mess up.

If you haven't made a backup of your database $conf, MAKE ONE NOW.

If you have made a backup of your database enter the number in the
middle of the previous paragraph.  Any other entry will abort.
EOS
  my $entered = <STDIN>;
  chomp $entered;
  if ($conf ne $conf) {
    print "Either you didn't backup your data of you didn't read the message.\n";
    exit;
  }
}

my $db = BSE::DB->single;

UNIVERSAL::isa($db, 'BSE::DB::Mysql')
  or die "Sorry, this only works for Mysql databases\n";

open STRUCT, "< mysql.str"
  or die "Cannot open structure file mysql.str: $!\n";
my %tables;
my $table;
while (<STRUCT>) {
  chomp;
  if (/^Table\s+([^,]+)/) {
    $table = $1;
  }
  elsif (/^Column\s+(\w+),([^,]+),(\w*),([^,]*),([^,]*)/) {
    $table or die "Column before Table";
    push(@{$tables{$table}{cols}}, 
	 {
	  field=>$1,
	  type=>$2,
	  null=>$3,
	  default=>$4,
	  extra=>$5,
	 });		    
  }
  elsif (/^Index\s+(\w+),(\d+),\[(\w+(?:,\w+)*)\]/) {
    $tables{$table}{indices}{$1} =
      {
       name=>$1,
       unique => $2,
       cols => [ split /,/, $3 ],
      };
  }
  else {
    die "Unknown structure command $_";
  }
}
close STRUCT;

# get a list of existing tables from the database
my $st = $db->{dbh}->prepare('show tables')
  or die "Cannot prepare 'show tables': ",$db->{dbh}->errstr,"\n";
$st->execute
  or die "Cannot execute 'show tables': ",$st->errstr,"\n";

my %ctables;
while (my $row = $st->fetchrow_arrayref) {
  $ctables{lc $row->[0]} = 1;
}

# ok, we know about the tables, check the database
for my $table (sort keys %tables) {
  print "Table $table\n" if $verbose;
  if (!$ctables{$table}) {
    # table doesn't exist - build it
    make_table($table, $tables{$table}{cols}, $tables{$table}{indices});
  }
  else {
    my $cols = $tables{$table}{cols};
    my @ccols = get_result("describe $table");
    @ccols <= @$cols
      or die "The $table table is bigger in your database";
    for my $i (0..$#ccols) {
      my $col = $cols->[$i];
      my $ccol = $ccols[$i];
      defined $ccol->{default} or $ccol->{default} = 'NULL';
      
      $col->{field} eq $ccol->{field}
	or die "Field name mismatch old: $ccol->{field} new: $col->{field}\n";
      
      if ($col->{type} ne $ccol->{type} || $col->{default} ne $ccol->{default}) {
	print "fixing type or default for $col->{field}\n" if $verbose;
	my $sql = "alter table $table modify ".create_clauses($col);
	run_sql($sql)
	  or die "Cannot fix $col->{field} type/default: $DBI::errstr\n";
      }
    }
    for my $i (@ccols .. $#$cols) {
      my $col = $cols->[$i];
      print "Adding column $col->{field}\n" if $verbose;
      my $sql = "alter table $table add ".create_clauses($col);
      run_sql($sql)
	or die "Cannot add column $col->{field}: $DBI::errstr\n";
    }
  }

  if (!$ctables{$table} && $pretend) {
    print "Cannot check indexes for $table since\n",
    "it doesn't exist and we're pretending.\n" if $verbose;
    next;
  }
  # indices
  # which ones exist
  my %cindices;
  for my $row (get_result("show index from $table")) {
    $cindices{$row->{key_name}} = 1;
  }
  my $indices = $tables{$table}{indices};
  for my $name (grep $_ ne 'PRIMARY', keys %$indices) {
    next if $cindices{$name};
    print "Creating index $name for $table\n" if $verbose;
    my $index = $indices->{$name};

    my $sql = "alter table $table add ";
    $sql .= $index->{unique} ? "unique " : "index ";
    $sql .= $name . " ";
    $sql .= "(" . join(",", @{$index->{cols}}) . ")";

    run_sql($sql)
      or die "Cannot add index $name: $DBI::errstr\n";
  }
}

sub make_table {
  my ($name, $cols, $indices) = @_;

  print "Creating table $name\n" if $verbose;
  my @def = create_clauses(@$cols);
  if ($indices->{PRIMARY}) {
    push(@def, 'primary key ('.join(',', @{$indices->{PRIMARY}{cols}}).')');
  }
  my $sql = "create table $name (\n";
  $sql .= join(",\n", @def);
  $sql .= "\n)\n";
  print "SQL to create $name: $sql\n" if $verbose > 2;
  run_sql($sql)
    or die "Cannot create table $name\n";
}

sub run_sql {
  my ($sql, @args) = @_;

  print "run_sql($sql, @args)\n" if $verbose > 1;
  return 1 if $pretend;
  my $sth = $db->{dbh}->prepare($sql)
    or die "Cannot prepare $sql: ",$db->{dbh}->errstr;
  return $sth->execute(@args);
}

sub get_result {
  my ($sql, @args) = @_;

  print "get_result($sql, @args)\n" if $verbose > 1;
  my $sth = $db->{dbh}->prepare($sql)
    or die "Cannot prepare $sql: ",$db->{dbh}->errstr;
  $sth->execute(@args)
    or die "Cannot execute $sql (@args): ",$sth->errstr;
  my @results;
  while (my $row = $sth->fetchrow_hashref('NAME_lc')) {
    push(@results, { %$row });
  }

  @results;
}

sub create_clauses {
  my (@cols) = @_;

  my @results;
  for my $col (@cols) {
    my $sql = $col->{field} . " " . $col->{type};
    $sql .= $col->{null} ? ' null' : ' not null';
    if ($col->{default} ne 'NULL') {
      $sql .= " default ";
      if ($col->{default} =~ /^\d+$/) {
	$sql .= $col->{default};
      }
      else {
	$sql .= $db->{dbh}->quote($col->{default});
      }
    }
    if ($col->{extra}) {
      $sql .= " ".$col->{extra};
    }
    push(@results, $sql);
  }

  if (wantarray) {
    return @results;
  }
  else {
    @results == 1 or die "Programming error!";
    return $results[0];
  }
}
