#!/usr/bin/perl -w
use strict;
use DBI;

my $dbh = DBI->connect('dbi:mysql:bodyscoop', 'root', '')
  or die "Cannot connect to database: $DBI::errstr";

my @tables = qw(article);

for my $tbl (@tables) {
  print "Table $tbl\n";
  open IN, "< $tbl.txt" or die "Cannot open $tbl.txt: $!";
  while (<IN>) {
    last if /^[^#]/;
  }
  chomp;
  my @columns = split /;/;
  $dbh->do("delete from $tbl")
    or die "Cannot delete from $tbl: $DBI::errstr";
  my $sql = "insert into $tbl (".join(",", @columns).") values (".
    join(",", ("?")x@columns).")";
  my $sth2 = $dbh->prepare($sql)
    or die "Cannot prepare $sql: $DBI::errstr";
  while (<IN>) {
    last if /^\s*$/;
    #print "$tbl: $_\n";
    if (/^[^#]/) {
      chomp;
      my @data = split /;/, $_, -1;
      if (@data != @columns) {
	print "Columns mismatch line $.:\n";
	for my $index (0..$#columns) {
	  print "$columns[$index]: ", defined $data[$index] ? $data[$index] : "<undef>", "\n";
	}
      }
      $sth2->execute(@data)
	or die "Cannot execute $sql: $DBI::errstr";
    }
  }
  close IN;
}

$dbh->disconnect;
