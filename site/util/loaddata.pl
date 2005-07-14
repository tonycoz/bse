#!perl -w
use strict;
use lib '../cgi-bin/modules';
use DevHelp::LoaderData;
use DBI;
use Constants;

my $datadir = shift
  or die "Usage: $0 directoryname\n";

my $dsn = $Constants::DSN;
my $dbuser = $Constants::UN;
my $dbpass = $Constants::PW;

# this is pretty rough, but good enough for now
my $dbh = DBI->connect($dsn, $dbuser, $dbpass)
  or die "Cannot connect to database: ",DBI->errstr;

my %tables;
opendir DATADIR, $datadir or die "Cannot open '$datadir' directory: $!";
while (my $inname = readdir DATADIR) {
  (my $table_name = $inname) =~ s/\.data$//
    or next;

  print "Loading table $table_name\n";

  my @pkey = $dbh->primary_key(undef, $dbuser, $table_name);
  unless (@pkey) {
    # look for a file with it
    open PKEY, "< $datadir/$table_name.pkey"
      or die "No primary key info found for $table_name";
    @pkey = <PKEY>;
    chomp @pkey;
    @pkey = grep /\S/, @pkey;
    close PKEY;
  }

  my $del_sql = "delete from $table_name where "
    . join(" and ", map "$_ = ?", @pkey);

  open DATA, "< $datadir/$inname"
    or die "Cannot open $datadir/$inname: $!";

  my $datafile = DevHelp::LoaderData->new(\*DATA)
    or die;

  while (my $row = $datafile->read) {
    for my $pkey_col (@pkey) {
      unless (exists $row->{$pkey_col}) {
	die "Missing value for $pkey_col in record ending $. of $inname\n";
      }
    }
    defined($dbh->do($del_sql, {}, @{$row}{@pkey}))
      or die "Error deleting old record: ", DBI->errstr;

    my $add_sql = "insert into $table_name(" .
      join(",", keys %$row) . ") values (".
	join(",", ("?") x keys %$row) . ")";
    defined($dbh->do($add_sql, {}, values %$row))
      or die "Error adding new record ($add_sql): ", DBI->errstr;
  }
  
  close DATA;
}
close DATADIR;

$dbh->disconnect;
