#!perl -w
use strict;
use lib '../cgi-bin/modules';
use DBI;
use BSE::DB;
use Getopt::Long;

my $verbose;
my $pretend;
my $didbackup;
my $input = "mysql.str";
my $wanthelp;

Getopt::Long::Configure('bundling');
GetOptions("v:i", \$verbose,
	   "n", \$pretend,
	   "b", \$didbackup,
	   "i=s", \$input,
	   "h", \$wanthelp);
$verbose = 1 if defined $verbose && $verbose == 0;
$verbose = 0 unless $verbose;

help() if $wanthelp;

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
  if ($entered ne $conf) {
    print "Either you didn't backup your data of you didn't read the message.\n";
    exit;
  }
}

my $db = BSE::DB->single;

UNIVERSAL::isa($db, 'BSE::DB::Mysql')
  or die "Sorry, this only works for Mysql databases\n";

open STRUCT, "< $input"
  or die "Cannot open structure file $input: $!\n";
my %tables;
my $table;
while (<STRUCT>) {
  chomp;
  tr/\r//d;
  if (/^Table\s+([^,]+)/) {
    $table = $1;
  }
  elsif (/^Engine (\w+)/) {
    $table or die "Engine before Table";
    $tables{$table}{engine} = $1;
  }
  elsif (/^Column\s+(\w+);([^;]+);(\w*);([^;]*);([^;]*)/) {
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
  elsif (/^Index\s+(\w+);(\d+);\[(\w+(?:;\w+)*)\]/) {
    $tables{$table}{indices}{$1} =
      {
       name=>$1,
       unique => $2,
       cols => [ split /;/, $3 ],
      };
  }
  else {
    die "Unknown structure command $_";
  }
}
close STRUCT;

# get a list of existing tables from the database
my $st = $db->{dbh}->prepare('show table status')
  or die "Cannot prepare 'show tables': ",$db->{dbh}->errstr,"\n";
$st->execute
  or die "Cannot execute 'show tables': ",$st->errstr,"\n";

my %ctables;
my %current_engines;
while (my $row = $st->fetchrow_arrayref) {
  $ctables{lc $row->[0]} = 1;
  $current_engines{lc $row->[0]} = $row->[1];
}

# ok, we know about the tables, check the database
for my $table (sort keys %tables) {
  my $want_engine = $tables{$table}{engine};

  print "Table $table\n"
    if $verbose;

  if (!$ctables{$table}) {
    # table doesn't exist - build it
    make_table($table, $tables{$table}{cols}, $tables{$table}{indices},
	       $want_engine);
  }
  else {
    my $cols = $tables{$table}{cols};
    my @ccols = get_result("describe $table");
    @ccols <= @$cols
      or die "The $table table is bigger in your database";
    my @alters;
    if ($want_engine &&
	lc $want_engine ne lc $current_engines{lc $table}) {
      print STDERR "Changing engine type to $want_engine\n"
	if $verbose;
      push @alters, qq!type = $want_engine!;
    }
    for my $i (0..$#ccols) {
      my $col = $cols->[$i];
      my $ccol = $ccols[$i];
      if ($ccol->{type} =~ /^varchar\((\d+)\) binary$/) {
	$ccol->{type} = "varbinary($1)";
      }
      defined $ccol->{default} or $ccol->{default} = 'NULL';
      if ($col->{type} eq 'timestamp') {
	$col->{default} = $ccol->{default} = 'current_timestamp';
      }
      
      $col->{field} eq $ccol->{field}
	or die "Field name mismatch old: $ccol->{field} new: $col->{field}\n";

      if ($col->{null} ne $ccol->{null}
	  || $col->{type} ne $ccol->{type} 
	  || $col->{default} ne $ccol->{default}) {
	print "fixing type or default for $col->{field}\n" if $verbose;
	if ($verbose > 1) {
	  print "old null: $ccol->{null}  new null: $col->{null}\n"
	    if $ccol->{null} ne $col->{null};
	  print "old type: $ccol->{type}  new type: $col->{type}\n"
	    if $ccol->{type} ne $col->{type};
	  print "old default: $ccol->{default}  new default: $col->{default}\n"
	    if $ccol->{default} ne $col->{default};
	}
	push @alters, ' modify ' . create_clauses($col);
      }
    }
    for my $i (@ccols .. $#$cols) {
      my $col = $cols->[$i];
      print "Adding column $col->{field}\n" if $verbose;
      push @alters, 'add ' . create_clauses($col);
    }
    if (@alters) {
      my $sql = "alter table $table ".join(', ', @alters);
      run_sql($sql)
	or die "Cannot run $sql (column type/default/null): $DBI::errstr\n";
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
    my $index = $indices->{$name};
    print "Creating index $name(@{$index->{cols}}) for $table\n" if $verbose;

    my $sql = "alter table $table add ";
    $sql .= $index->{unique} ? "unique " : "index ";
    $sql .= $name . " ";
    $sql .= "(" . join(",", map("`$_`", @{$index->{cols}})) . ")";

    run_sql($sql)
      or die "Cannot add index $name: $DBI::errstr\n";
  }
}

sub make_table {
  my ($name, $cols, $indices, $engine) = @_;

  print "Creating table $name\n" if $verbose;
  my @def = create_clauses(@$cols);
  if ($indices->{PRIMARY}) {
    push(@def, 'primary key ('.join(',', @{$indices->{PRIMARY}{cols}}).')');
  }
  my $sql = "create table $name (\n";
  $sql .= join(",\n", @def);
  $sql .= "\n)";
  if (defined $engine) {
    $sql .= "type = $engine";
  }
  $sql .= "\n";
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
    my $sql = "`" . $col->{field} . "` " . $col->{type};
    $sql .= $col->{null} eq 'YES' ? ' null' : ' not null';
    if ($col->{default} ne 'NULL' &&
	($col->{type} =~ /char/i || $col->{default} =~ /\d/)) {
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

sub help {
  # dump the POD up to the AUTHOR heading
  while (<DATA>) {
    last if /^=head1 AUTHOR/;
    print;
  }
  exit;
}

__DATA__

=head1 NAME

upgrade_mysql.pl - upgrades the sites mysql database to the description in mysql.str

=head1 SYNOPSIS

  perl upgrade_mysql.pl [-bn] [-v [verbosity]]

=head1 DESCRIPTION

Upgrades your BSE database, as described in your Constants.pm to the
schema described in mysql.str.

BACKUP YOUR DATABASE BEFORE USING THIS TOOL.

=head1 OPTIONS

=over

=item -b

Asserts that the user has done a backup.  Avoids the interactive query
about having done a backup.

=item -n

Only check for the changes needed, rather than actually performing the
upgrade.  Since it's possible that tables might not exist when
checking for indices, this may give you some errors.

=item -v [verbosity]

Controls verbosity of output.  The default level (1), will produce
basic descriptions of what is happening, including which table is
being checked, and any changes being made.

Level 2 will print debug messages containing any SQL that's being
executed.

Level 3 prints information useful only to developers.

=item -i filename

Specify and input filename that isn't mysql.str.

=item -h

Display help.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 REVISION

$Revision$

=head1 SEE ALSO

bse

=cut
