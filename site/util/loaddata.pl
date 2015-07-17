#!perl -w
use strict;
use lib '../cgi-bin/modules';
use DevHelp::LoaderData;
use DBI;
use Constants;
use BSE::API qw(bse_cfg bse_init);
use BSE::DB;
use Cwd;

bse_init("../cgi-bin");

my $cfg = bse_cfg;

my $datadir = shift
  or die "Usage: $0 directoryname\n";

# this is pretty rough, but good enough for now
my $db = BSE::DB::single
  or die "Cannot connect to database: ",DBI->errstr;

my $dbh = $db->dbh;

my $dbuser = BSE::DB->dbuser;

my %tables;
opendir my $dh, $datadir or die "Cannot open '$datadir' directory: $!";
while (my $inname = readdir $dh) {
  (my $table_name = $inname) =~ s/\.data$//
    or next;

  print "Loading table $table_name\n";

  my @pkey = $dbh->primary_key(undef, $dbuser, $table_name);
  unless (@pkey) {
    # look for a file with it
    my $pkey_filename = "$datadir/$table_name.pkey";
    open my $pkeyfh, "<", $pkey_filename
      or die "No primary key info found for $table_name";
    @pkey = <$pkeyfh>;
    chomp @pkey;
    @pkey = grep /\S/, @pkey;
    @pkey
      or die "No primary key data found in $pkey_filename\n";
    close $pkeyfh;
  }

  my $del_sql = "delete from $table_name where "
    . join(" and ", map "$_ = ?", @pkey);

  open my $fh, "<", "$datadir/$inname"
    or die "Cannot open $datadir/$inname: $!";

  my $datafile = DevHelp::LoaderData->new($fh)
    or die;

  $db->do_txn
    (
     sub {
       while (my $row = $datafile->read) {
	 defined($dbh->do($del_sql, {}, @{$row}{@pkey}))
	   or die "Error deleting old record: ", DBI->errstr;

	 my $add_sql = "insert into $table_name(" .
	   join(",", map $dbh->quote_identifier($_), keys %$row) . ") values (".
	     join(",", ("?") x keys %$row) . ")";
	 defined($dbh->do($add_sql, {}, values %$row))
	   or die "Error adding new record ($add_sql): ", DBI->errstr;
       }
     }
    );

  close $fh;
}
close $dh;

$dbh->disconnect;
