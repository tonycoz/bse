#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::Cfg;
use BSE::API qw(bse_cfg bse_make_product bse_encoding);
use BSE::ProductImportXLS;
use Carp qw(confess);

chdir "$FindBin::Bin/../cgi-bin"
  or warn "Could not change to cgi-bin directory: $!\n";

my $verbose;
my $delete;
GetOptions("v", \$verbose,
	   "d", \$delete);
$verbose = defined $verbose;

my $cfg = bse_cfg();

my $profile = shift;
my $filename = shift
  or die "Usage: $0 profile filename\n";

my $importer = BSE::ProductImportXLS->new($cfg, $profile);

my $callback;
$verbose
  and $callback = sub { print "@_\n" };

$importer->process($filename, $callback);

if ($delete) {
  my @products = $importer->products;
  my @catalogs = $importer->catalogs;
  for my $product (@products) {
    print "Removing product $product->{id}: $product->{title}\n";
    $product->remove($cfg);
  }
  require BSE::Permissions;
  my $perms = BSE::Permissions->new($cfg);
  for my $catalog (reverse @catalogs) {
    my $msg;
    if ($perms->check_edit_delete_article({}, $catalog, '', \$msg)) {
      print "Removing catalog $catalog->{id}: $catalog->{title}\n";
      $catalog->remove($cfg);
    }
    else {
      print "Cannot remove $catalog->{id}: $msg\n";
    }
  }
}

my @errors = $importer->errors;
unless ($verbose) { # unless we already reported them
  print STDERR $_, "\n" for @errors;
}
@errors
  and exit 1;

exit;
