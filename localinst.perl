#!/usr/bin/perl -w
use strict;
#use File::Tree;
use File::Copy;
use lib 't';
use BSE::Test ();

my $dist = shift or die "Usage: $0 distdir [leavedb]";
my $leavedb = shift or 0;
my $instbase = shift || BSE::Test::base_dir() || die "No base_dir";

my $mysql = BSE::Test::mysql_name;

#  if (-e "$instbase/cgi-bin/modules/Constants.pm"
#      && !-e "$instbase/Constants.pm") {
#    system "cp $instbase/cgi-bin/modules/Constants.pm $instbase/Constants.pm"
#  }

system("rm -rf $instbase/cgi-bin")
  and die "Cannot remove cgi-bin";
system "rm -rf $instbase/data"
  and die "Cannot remove data";
system "rm -f $instbase/htdocs/{*.html,a/*.html,shop/*.html,images/*.jpg}"
  and die "Cannot remove htdocs";

system "cp -rf $dist/site/cgi-bin $instbase"
  and die "Cannot copy cgi-bin";

system "cp -rf $dist/site/htdocs $instbase"
  and die "Cannot copy htdocs";
system "cp -rf $dist/site/templates $instbase"
  and die "Cannot copy templates";
system "cp -rf $dist/site/data $instbase"
  and die "Cannot copy data";
system "cp -rf $dist/site/util $instbase";

print "Updating conf\n";
# try to update Constants.pm
open CON, "< $instbase/cgi-bin/modules/Constants.pm"
  or die "Cannot open Constants.pm";
my $con = do { local $/; <CON> };
close CON;

my $dbuser = BSE::Test::test_dbuser();
my $dbpass = BSE::Test::test_dbpass();

$con =~ s/(^\$DSN = ')[^']*/$1 . BSE::Test::test_dsn()/me;
$con =~ s/(^\$DBCLASS = ')[^']*/$1 . BSE::Test::test_dbclass()/me;
$con =~ s/(^\$UN = ')[^']*/$1$dbuser/m;
$con =~ s/(^\$PW = ')[^']*/$1$dbpass/m;
$con =~ s/(^\$BASEDIR = ')[^']+/$1 . BSE::Test::base_dir/me;
#$con =~ s/(^\$URLBASE = ["'])[^'"]+/$1 . BSE::Test::base_url/me;
#$con =~ s/(^\$SECURLBASE = ["'])[^'"]+/$1 . BSE::Test::test_securl/me;
$con =~ s/(^\$SESSION_CLASS = ["'])[^'"]+/$1 . BSE::Test::test_sessionclass()/me;
open CON, "> $instbase/cgi-bin/modules/Constants.pm"
  or die "Cannot open Constants.pm for write: $!";
print CON $con;
close CON;

# fix bse.cfg
open CFG, "< $instbase/cgi-bin/bse.cfg"
  or die "Cannot open $instbase/cgi-bin/bse.cfg: $!";
my $cfg = do { local $/; <CFG> };
close CFG;
$cfg =~ s/^name\s*=.*/name=Test Server/m;
$cfg =~ s/^url\s*=.*/"url=" . BSE::Test::base_url()/me;
$cfg =~ s/^secureurl\s*=.*/"secureurl=" . BSE::Test::base_url()/me;
my $uploads = "$instbase/uploads";
$cfg =~ s!^downloads\s*=.*!downloads=$uploads!m;
-d $uploads 
  or mkdir $uploads, 0777 
  or die "Cannot find or create upload directory: $!";
open CFG, "> $instbase/cgi-bin/bse.cfg"
  or die "Cannot create $instbase/cgi-bin/bse.cfg: $!";
print CFG $cfg;
close CFG;

# build the database
unless ($leavedb) {
  my $dsn = BSE::Test::test_dsn();
  if ($dsn =~ /:mysql:(?:database=)?(\w+)/) {
    my $db = $1;
    system "$mysql -u$dbuser -p$dbpass $db <$dist/schema/bse.sql"
      and die "Cannot initialize database";
    system "cd $instbase/util ; perl initial.pl"
      and die "Cannot load database";
  }
  else {
    print "WARNING: cannot install to $dsn database\n";
  }
}

  
