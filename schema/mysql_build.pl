#!perl -w
# Builds a dump of the database structure suitable for use by upgrade_mysql.pl
use DBI;
use strict;
my $db = 'bsebuilder';
my $un = 'bsebuilder';
my $pw = 'bsebuilder';
my $dist = shift || "schema/bse.sql";

my $dbh = DBI->connect("dbi:mysql:$db", $un, $pw)
  or die "Cannot connect to db: ",DBI->errstr;

my $tl = $dbh->prepare("show tables")
  or die "prepare show tables ",$dbh->errstr;
$tl->execute
  or die "execute show tables ",$tl->errstr;
# cleanup first
my @drop_tables;
while (my $row = $tl->fetchrow_arrayref) {
  push(@drop_tables, $row->[0]);
}
undef $tl;
my %tables = map { $_ => 1 } @drop_tables;
my $error;
my $dropped = 1;
# need this loop to handle references between tables restricting us
# from dropping them
while ($dropped && keys %tables) {
  my $dropped = 0;
  my @tables = keys %tables;
  for my $drop (@tables) { # not keys %tables, since we modify it
    if ($dbh->do("drop table $drop")) {
      ++$dropped;
      delete $tables{$drop};
    }
    else {
      $error = "Could not drop old table: ". $dbh->errstr;
    }
  }
}
if (keys %tables) {
  print "Could not drop bsebuilder tables:\n   ", join("\n  ", sort keys %tables), "\n";
  die $error;
}

system "mysql -u$un -p$pw $db <$dist"
  and die "Error loading database";

$tl = $dbh->prepare("show table status")
  or die "prepare show table status ",$dbh->errstr;
$tl->execute
  or die "execute show table status ",$tl->errstr;
my @tables;
my %engines;
while (my $row = $tl->fetchrow_arrayref) {
  push(@tables, $row->[0]);
  $engines{$row->[0]} = $row->[1];
}
undef $tl;

my @expected = qw(field type null key default extra);
my @want =     qw(field type null default extra);
for my $table (@tables) {
  print "Table $table\n";
  print "Engine $engines{$table}\n";
  my $ti = $dbh->prepare("describe $table")
    or die "prepare describe $table: ",$dbh->errstr;
  $ti->execute()
    or die "execute describe $table: ",$dbh->errstr;
  my @names = @{$ti->{NAME_lc}};
  my %names;
  @names{@names} = 0..$#names;
  for my $name (@expected) {
    exists $names{$name}
      or die "Didn't find expected field $name in describe table $table";
  }
  while (my $row = $ti->fetchrow_arrayref) {
    for my $name (@want) {
      defined $row->[$names{$name}] or $row->[$names{$name}] = "NULL";
      if ($name eq 'type' && 
	  $row->[$names{$name}] =~ /^varchar\((\d+)\) binary$/i) {
	$row->[$names{$name}] = "varbinary($1)";
      }
    }
    print "Column ",join(";",@$row[@names{@want}]),
    "\n";
  }
  undef $ti;
  my $ii = $dbh->prepare("show index from $table")
    or die "prepare show index from $table: ",$dbh->errstr;
  $ii->execute()
    or die "execute show index from $table: ",$dbh->errstr;
  my %indices;
  my %unique;
  while (my $row = $ii->fetchrow_hashref("NAME_lc")) {
    push(@{$indices{$row->{key_name}}}, 
	 [ $row->{column_name}, $row->{seq_in_index} ]);
    $unique{$row->{key_name}} = 0 + !$row->{non_unique};
  }
  #use Data::Dumper;
  #print Dumper(\%indices);
  for my $index (sort keys %indices) {
    my @sorted = sort { $a->[1] <=> $b->[1] } @{$indices{$index}};
    print "Index $index;$unique{$index};[",
      join(";", map $_->[0], @sorted),
      "]\n";
  }
}

$dbh->disconnect;
