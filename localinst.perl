#!/usr/bin/perl -w
use strict;
#use File::Tree;
use File::Copy;

my $dist = shift or die "Usage: $0 distdir [leavedb]";
my $leavedb = shift or 0;
my $instbase = shift || "/home/httpd/bsetest";

my $mysql = "/usr/local/mysql/bin/mysql";

if (-e "$instbase/cgi-bin/modules/Constants.pm"
    && !-e "$instbase/Constants.pm") {
  system "cp $instbase/cgi-bin/modules/Constants.pm $instbase/Constants.pm"
}
my $gotconf;
eval {
  require $instbase."/Constants.pm";
  $Constants::BASEDIR . $Constants::URLBASE . $Constants::SECURLBASE;
  ++$gotconf;
};

system("rm -rf $instbase/cgi-bin")
  and die "Cannot remove cgi-bin";
system "rm -rf $instbase/data"
  and die "Cannot remove data";
system "rm -f $instbase/htdocs/{*.html,a/*.html,shop/*.html,images/*.jpg}"
  and die "Cannot remove htdocs";

system "cp -rf $dist/site/cgi-bin $instbase"
  and die "Cannot copy cgi-bin";
unlink "$instbase/cgi-bin/bse.cfg";

system "cp -rf $dist/site/htdocs $instbase"
  and die "Cannot copy htdocs";
system "cp -rf $dist/site/templates $instbase"
  and die "Cannot copy templates";
system "cp -rf $dist/site/data $instbase"
  and die "Cannot copy data";
system "cp -rf $dist/site/util $instbase";

if ($gotconf) {
  print "Updating conf\n";
  # try to update Constants.pm
  open CON, "< $instbase/cgi-bin/modules/Constants.pm"
    or die "Cannot open Constants.pm";
  my $con = do { local $/; <CON> };
  close CON;

  if (defined $Constants::DB && !defined $Constants::DSN) {
    $Constants::DSN = 'dbi:mysql:'.$Constants::DB;
    $Constants::DBCLASS = "BSE::DB::Mysql";
    $Constants::SESSION_CLASS = "Apache::Session::MySQL";
  }
  $con =~ s/(^\$DSN = ')[^']*/$1$Constants::DSN/m;
  $con =~ s/(^\$DBCLASS = ')[^']*/$1$Constants::DBCLASS/m;
  $con =~ s/(^\$UN = ')[^']*/$1$Constants::UN/m;
  $con =~ s/(^\$PW = ')[^']*/$1$Constants::PW/m;
  $con =~ s/(^\$BASEDIR = ')[^']+/$1$Constants::BASEDIR/m;
  $con =~ s/(^\$URLBASE = ["'])[^'"]+/$1$Constants::URLBASE/m;
  $con =~ s/(^\$SECURLBASE = ["'])[^'"]+/$1$Constants::SECURLBASE/m;
  $con =~ s/(^\$SESSION_CLASS = ["'])[^'"]+/$1$Constants::SESSION_CLASS/m;
  open CON, "> $instbase/cgi-bin/modules/Constants.pm"
    or die "Cannot open Constants.pm for write: $!";
  print CON $con;
  close CON;

  # build the database
  unless ($leavedb) {
    if ($Constants::DSN =~ /:mysql:(?:database=)?(\w+)/) {
      my $db = $1;
      system "$mysql -u$Constants::UN -p$Constants::PW $db <$dist/schema/bse.sql"
	and die "Cannot initialize database";
      system "cd $instbase/util ; perl initial.pl"
	and die "Cannot load database";
    }
    else {
      print "WARNING: cannot install to $Constants::DSN database\n";
    }
  }
}
  
