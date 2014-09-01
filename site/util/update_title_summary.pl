#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_init bse_cfg);
use BSE::TB::Orders;
use BSE::TB::Products;

bse_init("../cgi-bin");

my @orders = BSE::TB::Orders->all;
my %products;
for my $order (@orders) {
  my @items = $order->items;
  for my $item (@items) {
    $products{$item->{productId}} = BSE::TB::Products->getByPkey($item->{productId});
    my $product = $products{$item->{productId}};
    unless ($product) {
      print STDERR "Product $item->{productId} not found for order $order->{id}\n";
      next;
    }
    $item->{title} eq '' 
      and $item->{title} = $product->{title};
    $item->{description} eq '' 
      and $item->{description} = $product->{description};
    $item->save;
  }
}
