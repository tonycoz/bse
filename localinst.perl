#!/usr/bin/perl -w
use strict;

my $dist = shift or die "Usage: $0 distdir";

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
system "rm -rf $instbase/htdocs"
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

if ($gotconf) {
  print "Updating conf\n";
  # try to update Constants.pm
  open CON, "< $instbase/cgi-bin/modules/Constants.pm"
    or die "Cannot open Constants.pm";
  my $con = do { local $/; <CON> };
  close CON;

  $con =~ s/(^\$DB = ')[^']*/$1$Constants::DB/m;
  $con =~ s/(^\$UN = ')[^']*/$1$Constants::UN/m;
  $con =~ s/(^\$PW = ')[^']*/$1$Constants::PW/m;
  $con =~ s/(^\$BASEDIR = ')[^']+/$1$Constants::BASEDIR/m;
  $con =~ s/(^\$URLBASE = ["'])[^'"]+/$1$Constants::URLBASE/m;
  $con =~ s/(^\$SECURLBASE = ["'])[^'"]+/$1$Constants::SECURLBASE/m;
  open CON, "> $instbase/cgi-bin/modules/Constants.pm"
    or die "Cannot open Constants.pm for write: $!";
  print CON $con;
  close CON;

  # build the database
  system "$mysql -u$Constants::UN -p$Constants::PW $Constants::DB <$dist/schema/bse.sql"
    and die "Cannot initialize database";
  system "cd $instbase/util ; perl initial.pl"
    and die "Cannot load database";
}
