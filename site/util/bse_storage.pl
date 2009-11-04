#!perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::Cfg;
use BSE::StorageMgr::Images;
use BSE::StorageMgr::Files;
use BSE::StorageMgr::Thumbs;
use Getopt::Long;

my $verbose;
my $noaction;

GetOptions("v", \$verbose,
	   'n', \$noaction);

chdir "$FindBin::Bin/../cgi-bin"
  or warn "Could not change to cgi-bin directory: $!\n";

my $cfg = BSE::Cfg->new;

my $images = BSE::StorageMgr::Images->new(cfg => $cfg);
my $files = BSE::StorageMgr::Files->new(cfg => $cfg);
my $thumbs = BSE::StorageMgr::Thumbs->new(cfg => $cfg);
my %stores =
  (
   images => $images,
   files => $files,
   thumbs => $thumbs,
  );

my $action = shift;
defined $action or $action = '';

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
  if ($noaction) {
    $opts{noaction} = 1;
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
  -n - don't touch the storage during a sync (shows progress, but performs no updates)
Commands:
  list - list the files stored on each non-local storage
  sync - synchronize the files stored to the storages selected in 
         their records
  fixsrc - update the src value for each image/file (recommended on 
           upgrade)
EOS
}
