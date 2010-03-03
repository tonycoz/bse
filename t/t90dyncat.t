#!perl -w
use strict;
use BSE::Test ();
use Test::More tests=>17;
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
require BSE::TB::ProductOptions;
require BSE::TB::ProductOptionValues;
require BSE::API;
require BSE::Dynamic::Catalog;
require BSE::Request::Test;
my $req = BSE::Request::Test->new(cfg => $cfg);
my $gen = BSE::Dynamic::Catalog->new($req);
BSE::API->import(qw/bse_make_catalog bse_make_product bse_add_step_child/);

sub dyn_template_test($$$$);

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

my $parent3 = bse_make_catalog
  (
   cfg => $cfg,
   parentid => $parent->{id},
   title => "third test catalog",
   body => "third test catalog"
  );

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

# give the last an option
my $order = time();
my $opt = BSE::TB::ProductOptions->make
  (
   product_id => $prods[2]->id,
   name => "Test Option",
   display_order => $order++,
  );
BSE::TB::ProductOptionValues->make
  (
   product_option_id => $opt->id,
   value => "Alpha",
   display_order => $order++,
  );
BSE::TB::ProductOptionValues->make
  (
   product_option_id => $opt->id,
   value => "Beta",
   display_order => $order++,
  );

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

my $prod_step_link = bse_add_step_child
  (
   cfg => $cfg,
   parent => $parent,
   child => $prod4
  );
ok($prod_step_link, "made the product step link");

bse_add_step_child
  (
   cfg => $cfg,
   parent => $parent,
   child => $parent2
  );

dyn_template_test "dynallprods", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallprods:><:
dynallprod id:><:ifDynAnyProductOptions:> options<:or:><:eif:>
<:iterator end dynallprods:>
TEMPLATE
$prod4->{id}
$prods[0]{id}
$prods[1]{id}
$prods[2]{id} options

EXPECTED

dyn_template_test "dynallcats", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallcats:><:
dynallcat id:>
<:iterator end dynallcats:>
TEMPLATE
$parent2->{id}
$parent3->{id}

EXPECTED

$prod4->remove($cfg);
for my $prod (@prods) {
  $prod->remove($cfg);
}
$parent3->remove($cfg);
$parent2->remove($cfg);
$parent->remove($cfg);

sub dyn_template_test($$$$) {
  my ($tag, $article, $template, $expected) = @_;

  #diag "Template >$template<";
  my $gen = 
    eval {
      my $gen_class = $article->{generator};
      $gen_class =~ s/.*\W//;
      $gen_class = "BSE::Dynamic::".$gen_class;
      (my $filename = $gen_class) =~ s!::!/!g;
      $filename .= ".pm";
      require $filename;
      $gen_class->new($req);
    };
  ok($gen, "$tag: created generator $article->{generator}");
  diag $@ unless $gen;

  # get the template - always regen it
  my $work_template = _generate_dyn_template($article, $template);

  my $result;
 SKIP: {
    skip "$tag: couldn't make generator", 1 unless $gen;
    eval {
      $result =
	$gen->generate($article, $work_template);
    };
    ok($result, "$tag: generate content");
    diag $@ unless $result;
  }
 SKIP: {
     skip "$tag: couldn't gen content", 1 unless $result;
     is($result->{content}, $expected, "$tag: comparing");
   }
}

sub _generate_dyn_template {
  my ($article, $template) = @_;

  my $articles = 'Articles';
  my $genname = $article->{generator};
  eval "use $genname";
  $@ && die $@;
  my $gen = $genname->new(articles=>$articles, cfg=>$cfg, top=>$article);

  return $gen->generate_low($template, $article, $articles, 0);
}
