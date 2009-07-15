#!perl -w
use strict;
use BSE::Test ();
use Test::More tests=>20;
use File::Spec;
use FindBin;
my $cgidir = File::Spec->catdir(BSE::Test::base_dir, 'cgi-bin');
ok(chdir $cgidir, "switch to CGI directory");
push @INC, 'modules';
require BSE::Cfg;
my $cfg = BSE::Cfg->new;
# create some articles to test with
require Articles;
require Products;
require BSE::API;
BSE::API->import(qw/bse_make_catalog bse_make_product bse_add_step_child/);

my $parent = bse_make_catalog
  (
   cfg => $cfg,
   title => "test catalog",
   body => "Test catalog for catalog tests"
  );

ok($parent, "made a catalog");
is($parent->{generator}, "Generate::Catalog", "check generator");

my $parent2 = bse_make_catalog
  (
   cfg => $cfg,
   title => "second test catalog",
   body => "second test catalog"
  );

ok($parent2, "got second catalog");
isnt($parent->{displayOrder}, $parent2->{displayOrder},
     "make sure we get unique display orders");

# add some products
my @prods;
my $price = 1000;
my %prod_order;
for my $title (qw/prod1 prod2 prod3/) {
  my $prod = bse_make_product
    (
     cfg => $cfg,
     parentid => $parent->{id},
     title => $title,
     retailPrice => $price,
     body => $title,
     product_code => $title
    );
  ok($prod, "make product $title/$prod->{id}");
  unshift @prods, $prod;
  $prod_order{$prod->{displayOrder}} = 1;
  $price += 500;
}
is(scalar keys %prod_order, 3, "make sure display orders unique");

my $prod4 = bse_make_product
  (
   cfg => $cfg,
   parentid => $parent2->{id},
   title => "other catalog prod",
   retailPrice => $price,
   body => "other catalog prod",
   product_code => "other catalog prod"
  );
ok($prod4, "made prod in other catalog");

{
  my @kids = $parent->all_visible_products;
  is(@kids, 3, "got all the normal products");
  for my $index (0 .. $#kids) {
    is($kids[$index]{id}, $prods[$index]{id}, "check id at $index");
  }
}

my $step_link = bse_add_step_child
  (
   cfg => $cfg,
   parent => $parent,
   child => $prod4
  );
ok($step_link, "made the step link");

{
  my @kids = $parent->all_visible_products;
  is(@kids, 4, "got all the normal products and step");
  my @check = ( $prod4, @prods );
  for my $index (0 .. $#check) {
    is($kids[$index]{id}, $check[$index]{id}, "check id at $index");
  }
}

$prod4->remove($cfg);
for my $prod (@prods) {
  $prod->remove($cfg);
}
$parent->remove($cfg);
$parent2->remove($cfg);

