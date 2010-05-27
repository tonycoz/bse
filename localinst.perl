#!/usr/bin/perl -w
use strict;
#use File::Tree;
use File::Copy;
use lib 't';
use BSE::Test ();
require ExtUtils::Manifest;

my $dist = shift or die "Usage: $0 distdir [leavedb]";
my $leavedb = shift or 0;
my $instbase = shift || BSE::Test::base_dir() || die "No base_dir";

my $mysql = BSE::Test::mysql_name;

#  if (-e "$instbase/cgi-bin/modules/Constants.pm"
#      && !-e "$instbase/Constants.pm") {
#    system "cp $instbase/cgi-bin/modules/Constants.pm $instbase/Constants.pm"
#  }

#system("rm -rf $instbase/cgi-bin")
#  and die "Cannot remove cgi-bin";
#system "rm -rf $instbase/data"
#  and die "Cannot remove data";
#system "rm -f $instbase/htdocs/{*.html,a/*.html,shop/*.html,images/*.jpg}"
#  and die "Cannot remove htdocs";

-d "$instbase/cgi-bin" or mkdir "$instbase/cgi-bin"
  or die "Cannot create $instbase/cgi-bin: $!";
system "cp -rf $dist/site/cgi-bin/* $instbase/cgi-bin"
  and die "Cannot copy cgi-bin";

my $perl = BSE::Test::test_perl();
if ($perl ne '/usr/bin/perl') {
  my $manifest = ExtUtils::Manifest::maniread();

  for my $file (grep /\.pl$/, keys %$manifest) {
    (my $work = $file) =~ s!^site!!;
    next unless $work =~ /cgi-bin/;
    my $full = $instbase . $work;
    open SCRIPT, "< $full" or die "Cannot open $full: $!";
    binmode SCRIPT;
    my @all = <SCRIPT>;
    close SCRIPT;
    $all[0] =~ s/^#!\S*perl\S*/#!$perl/;
    open SCRIPT, "> $full" or die "Cannot create $full: $!";
    binmode SCRIPT;
    print SCRIPT @all;
    close SCRIPT;
  }
}

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

#$con =~ s/(^\$DSN = ')[^']*/$1 . BSE::Test::test_dsn()/me;
#$con =~ s/(^\$DBCLASS = ')[^']*/$1 . BSE::Test::test_dbclass()/me;
#$con =~ s/(^\$UN = ')[^']*/$1$dbuser/m;
#$con =~ s/(^\$PW = ')[^']*/$1$dbpass/m;
$con =~ s/(^\$BASEDIR = ')[^']+/$1 . BSE::Test::base_dir/me;
#$con =~ s/(^\$URLBASE = ["'])[^'"]+/$1 . BSE::Test::base_url/me;
#$con =~ s/(^\$SECURLBASE = ["'])[^'"]+/$1 . BSE::Test::test_securl/me;
$con =~ s/(^\$SESSION_CLASS = [\"\'])[^\'\"]+/$1 . BSE::Test::test_sessionclass()/me;
open CON, "> $instbase/cgi-bin/modules/Constants.pm"
  or die "Cannot open Constants.pm for write: $!";
print CON $con;
close CON;


# rebuild the config file
# first load values from the test.cfg file
my $conffile = BSE::Test::test_conffile();
my %conf;
$conf{site}{url} = BSE::Test::base_url();
$conf{site}{secureurl} = BSE::Test::base_securl();
my $uploads = "$instbase/uploads";
$conf{paths}{downloads} = $uploads;
my $templates = "$instbase/templates";
$conf{paths}{templates} = $templates;
open TESTCONF, "< $conffile"
  or die "Could not open config file $conffile: $!";
while (<TESTCONF>) {
  chomp;
  /^\s*(\w[^=]*\w)\.([\w-]+)\s*=\s*(.*)\s*$/ or next;
  $conf{lc $1}{lc $2} = $3;
}

$uploads = $conf{paths}{downloads};
# create installation config

$conf{db}{class} = BSE::Test::test_dbclass();
$conf{db}{dsn} = BSE::Test::test_dsn();
$conf{db}{user} = $dbuser;
$conf{db}{password} = $dbpass;

open CFG, "> $instbase/cgi-bin/bse-install.cfg"
  or die "Cannot create $instbase/cgi-bin/bse-install.cfg: $!";

print CFG "; DO NOT EDIT - created during installation\n";
for my $section_name (keys %conf) {
  print CFG "[$section_name]\n";
  my $section = $conf{$section_name};
  for my $key (keys %$section) {
    print CFG "$key=$section->{$key}\n";
  }
  print CFG "\n";
}

close CFG;

-d $uploads 
  or mkdir $uploads, 0777 
  or die "Cannot find or create upload directory: $!";


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

  
