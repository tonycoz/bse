#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::Cfg;
use BSE::TB::Products;

chdir "$FindBin::Bin/../cgi-bin"
  or warn "Could not change to cgi-bin directory: $!\n";

my @products = BSE::TB::Products->all;
for my $product (@products) {
  if ($product->{body} =~ s/\bpcode:\s*(\S+)//) {
    $product->{product_code} = $1;
    $product->save;
  }
}
