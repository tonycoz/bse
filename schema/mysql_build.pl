#!perl -w
# Builds a dump of the database structure suitable for use by upgrade_mysql.pl
use DBI;
use strict;
my $db = 'bsebuilder';
my $un = 'bsebuilder';
my $pw = 'bsebuilder';
my $dist = "/home/tony/dev/bse/base/bse/schema/bse.sql";

system "/usr/local/mysql/bin/mysql -u$un -p$pw $db <$dist"
  and die "Error loading database";
my $dbh = DBI->connect("dbi:mysql:$db", $un, $pw)
  or die "Cannot connect to db: ",DBI->errstr;

my $tl = $dbh->prepare("show tables")
  or die "prepare show tables ",$dbh->errstr;
$tl->execute
  or die "execute show tables ",$tl->errstr;
my @tables;
while (my $row = $tl->fetchrow_arrayref) {
  push(@tables, $row->[0]);
}
undef $tl;

my @expected = qw(field type null key default extra);
my @want = qw(field type null default extra);
for my $table (@tables) {
  print "Table $table\n";
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
    }
    print "Column ",join(",",@$row[@names{@want}]),
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
    print "Index $index,$unique{$index},[",
      join(",", map $_->[0], @sorted),
      "]\n";
  }
}

$dbh->disconnect;
