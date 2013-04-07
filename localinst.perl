#!/usr/bin/perl -w
use strict;
#use File::Tree;
use File::Copy;
use lib 'lib';
use BSE::Install qw(util_dir cgi_dir public_html_dir templates_dir data_dir mysql_name);
#use BSE::Test ();
use ExtUtils::Manifest qw(maniread);
use File::Copy qw(copy);
use File::Spec;
use File::Path qw(make_path);
use Getopt::Long;

my $verbose;
GetOptions("v|verbose" => \$verbose);

my $dist = shift or die "Usage: $0 distdir [leavedb]";
my $leavedb = shift or 0;

my $mysql = mysql_name();

my $cfg = BSE::Install::cfg();

my $manifest = maniread();

install_files("site/htdocs/", public_html_dir());
install_files("site/templates/", templates_dir());
install_files("site/cgi-bin", cgi_dir());
install_files("site/util/", util_dir());
install_files("site/data/", data_dir());

my $perl = BSE::Install::perl();
if ($perl ne '/usr/bin/perl') {
  my $manifest = ExtUtils::Manifest::maniread();

  for my $file (keys %$manifest) {
    (my $work = $file) =~ s!^site/!!;
    $work =~ s(^(cgi-bin|util)/)()
      or next;
    my $base = $work eq "util" ? util_dir() : cgi_dir();
    my $full = File::Spec->catfile($base, $work);
    open my $script, "<", $full
      or next;
    binmode $script;
    my $first = <$script>;
    if ($first =~ s/^#!\S*perl\S*/#!$perl/) {
      my @all = <$script>;
      close $script;
      open my $out_script, ">", $full or die "Cannot create $full: $!";
      binmode $out_script;
      print $out_script $first, @all;
      close $out_script;
    }
  }
}

print "Updating conf\n";

my $conf_src = BSE::Install::conffile();
my $conf_dest = File::Spec->catfile(cgi_dir(), "bse-install.cfg");
copy($conf_src, $conf_dest)
  or die "Cannot copy $conf_src to $conf_dest: $!\n";

#-d $uploads 
#  or mkdir $uploads, 0777 
#  or die "Cannot find or create upload directory: $!";

my $dbuser = BSE::Install::db_user();
my $dbpass = BSE::Install::db_password();

# build the database
my $dsn = BSE::Install::db_dsn();
if ($dsn =~ /:mysql:(?:database=)?(\w+)/) {
  my $db = $1;

  unless ($leavedb) {
    system "$mysql -u$dbuser -p$dbpass $db <$dist/schema/bse.sql"
      and die "Cannot initialize database";
    system "cd ".util_dir." ; $perl initial.pl"
      and die "Cannot load database";
  }

  # always load stored procedures
  system qq($mysql "-u$dbuser" "-p$dbpass" "$db" <$dist/schema/bse_sp.sql)
    and die "Error loading stored procedures\n";
}
else {
  print "WARNING: cannot install to $dsn database\n";
}

sub install_files {
  my ($prefix, $destbase) = @_;

  print "Install $prefix to $destbase\n";
  for my $file (sort grep /^\Q$prefix/, keys %$manifest) {
    (my $rel = $file) =~ s/^\Q$prefix//;
    my $src = File::Spec->catfile($dist, $file);
    my $dest = File::Spec->catfile($destbase, $rel);
    my ($destvol, $destdir) = File::Spec->splitpath($dest);
    my $destpath = File::Spec->catdir($destvol, $destdir);
    unless (-e $destpath) {
      make_path($destpath); # croak on error
    }
    elsif (!-d $destpath) {
      die "$destpath isn't a directory!\n";
    }
    print "  Copy $rel to $dest\n" if $verbose;
    copy($src, $dest)
      or die "Cannot copy $src to $dest: $!\n";
  }
}
