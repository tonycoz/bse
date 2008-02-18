#!perl -w
use strict;
use lib '../cgi-bin/modules';
use BSE::Cfg;
use BSE::StorageMgr::Images;
use BSE::StorageMgr::Files;
use Getopt::Long;

my $verbose;

GetOptions("v", \$verbose);

chdir "$FindBin::Bin/../cgi-bin"
  or warn "Could not change to cgi-bin directory: $!\n";

my $cfg = BSE::Cfg->new;

my $images = BSE::StorageMgr::Images->new(cfg => $cfg);
my $files = BSE::StorageMgr::Files->new(cfg => $cfg);
my %stores =
  (
   images => $images,
   files => $files,
  );

my $action = shift;
defined $action || $action = '';

if ($action eq 'list') {
  for my $type (sort keys %stores) {
    my @stores = $stores{$type}->all_stores;
    print "Type $type\n";
    for my $store (grep $_->name ne 'local', @stores) {
      print " Storage ", $store->description, " (", $store->name, ")\n";
      print "  $_\n" for $store->list;
    }
  }
}
elsif ($action eq 'sync') {
  my %opts;

  if ($verbose) {
    $opts{print} = sub { print "  ", @_, "\n"; };
  }
  for my $type (sort keys %stores) {
    print "Type $type\n" if $verbose;
    my $mgr = $stores{$type};
    $mgr->sync(%opts);
  }
}
elsif ($action eq 'fixsrc') {
  for my $type (sort keys %stores) {
    print "Type $type\n" if $verbose;
    $stores{$type}->fixsrc;
  }
}
else {
  print <<EOS;
Usage: $0 [-v] command
  -v - display progress information
Commands:
  list - list the files stored on each non-local storage
  sync - synchronize the files stored to the storages selected in 
         their records
  fixsrc - update the src value for each image/file (recommended on 
           upgrade)
EOS
}
