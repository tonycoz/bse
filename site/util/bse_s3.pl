#!perl -w
use strict;
use lib '../cgi-bin/modules';
use BSE::Cfg;
use BSE::Storage::AmazonS3;

chdir "$FindBin::Bin/../cgi-bin"
  or warn "Could not change to cgi-bin directory: $!\n";

my $cfg = BSE::Cfg->new;

my $store_name = shift;
my $action = shift
  or die "Usage: $0 storage action\n";

$cfg->entry("storage $store_name", "class", '') eq 'BSE::Storage::AmazonS3'
  or die "$0: $store_name is not an S3 storage\n";
my $store = BSE::Storage::AmazonS3->new(cfg => $cfg, name => $store_name);
$store->cmd($action, @ARGV);
