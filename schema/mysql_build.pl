#!perl -w
# Builds a dump of the database structure suitable for use by upgrade_mysql.pl
use DBI;
my $db = 'bsebuilder';
my $un = 'bsebuilder';
my $pw = 'bsebuilder';
my $dist = "/home/tony/dev/bse/base/bse/schema/bse.sql";

system "/usr/local/mysql/bin/mysql -u$un -p$pw $db <$dist"
  and die "Error loading database";
my $dbh = DBI->connect('dbi:mysql:$db', $un, $pw)
  or die "Cannot connect to db: ",DBI->errstr;

my $ti = $dbh->table_index
  or die "Cannot get table info\n";

