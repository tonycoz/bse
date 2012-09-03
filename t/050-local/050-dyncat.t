#!perl -w
use strict;
use BSE::Test ();
use Test::More tests => 95;
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
use Carp qw(confess);

$SIG{__DIE__} = sub { confess @_ };

$| = 1;

my %cgi =
  (
   test1 => "one",
   test2 => [ qw/two three/ ],
   test3 => "Size: Medium",
   test4 => [ "Size: Medium", "Colour: Red" ],
   test5 => "Size:Medium/Colour:Red/Style:Pretty",
   test6 => "/Size:Medium//Colour:Red/",
   pp => 5,
   p => 2,
  );
my $req = BSE::Request::Test->new(cfg => $cfg, params => \%cgi);
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

sleep 1;
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
my %prods;
my $price = 1000;
my %prod_order;
for my $title (qw/prod1 prod2 prod3 prod4 prod5 prod6 prod7 prod8 prod9 prod10/) {
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
  $prods{$prod->title} = $prod;
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

is(scalar keys %prod_order, 10, "make sure display orders unique");

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

{
  my %tags =
    (
     prod1 => [ "Size: Small", "Colour: Red", "ABC" ],
     prod2 => [ "Size: Small", "Colour: Blue" ],
     prod3 => [ "Size: Small", "Colour: Green", "ABC" ],
     prod4 => [ "Size: Medium", "Colour: Red" ],
     prod5 => [ "Size: Medium", "Colour: Blue", "Colour: Purple" ],
     prod6 => [ "Size: Medium", "Colour: Green" ],
     prod7 => [ "Size: Medium", "Colour: Black" ],
     prod8 => [ "Size: Large", "Colour: Red" ],
     prod9 => [ "Size: Large", "Colour: Blue" ],
     prod10 => [ "Size: Large", "Colour: Green", "XYZ" ],
    );
  # set some tags
  for my $key (sort keys %tags) {
    my $error;
    ok($prods{$key}->set_tags($tags{$key}, \$error),
       "set tags on $key")
      or print("# error: $error");

    my @set = sort @{$tags{$key}};
    my @tags = sort $prods{$key}->tags;
    is_deeply(\@set, \@tags, "check tags set for $key");
  }

  my $error;
  $parent->set_tags([ "Brand: Foo", "Class: Network" ], \$error);
}

dyn_template_test "dynallprods", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallprods:><:
dynallprod id:><:ifDynAnyProductOptions:> options<:or:><:eif:>
<:iterator end dynallprods:>
TEMPLATE
$prod4->{id}
$prods[0]{id}
$prods[1]{id}
$prods[2]{id} options
$prods[3]{id}
$prods[4]{id}
$prods[5]{id}
$prods[6]{id}
$prods[7]{id}
$prods[8]{id}
$prods[9]{id}

EXPECTED

dyn_template_test "article tags", $parent, <<TEMPLATE, <<EXPECTED;
<:dynarticle tags:>
TEMPLATE
Brand: Foo/Class: Network
EXPECTED

dyn_template_test "dynallprods tag filter", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallprods tags: "Size: Small" :><:
dynallprod title:>
<:iterator end dynallprods:>
TEMPLATE
prod3
prod2
prod1

EXPECTED

dyn_template_test "dynallprods tag filter cgi", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallprods tags: [lcgi test3] :><:
dynallprod title:>
<:iterator end dynallprods:>
TEMPLATE
prod7
prod6
prod5
prod4

EXPECTED

dyn_template_test "dynallprods tag filter", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynunused_tagcats dynallprods tags: "Size: Small" :><:
ifDynunused_tagcat nocat:><:or:><:
dynunused_tagcat name:>:
<:eif
:><:iterator begin dynunused_tags:> <:dynunused_tag val:> (<:dynunused_tag count:>)
<:iterator end dynunused_tags:><:iterator end dynunused_tagcats :>
TEMPLATE
 ABC (2)
Colour:
 Blue (1)
 Green (1)
 Red (1)

EXPECTED

dyn_template_test "unused tags no highlander", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynunused_tagcats dynallprods tags: "Colour: Blue" :><:
ifDynunused_tagcat nocat:><:or:><:
dynunused_tagcat name:>:
<:eif
:><:iterator begin dynunused_tags:> <:dynunused_tag val:> (<:dynunused_tag count:>)
<:iterator end dynunused_tags:><:iterator end dynunused_tagcats :>
TEMPLATE
Colour:
 Purple (1)
Size:
 Large (1)
 Medium (1)
 Small (1)

EXPECTED

dyn_template_test "unused tags highlander", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynunused_tagcats dynallprods onlyone tags: "Colour: Blue" :><:
ifDynunused_tagcat nocat:><:or:><:
dynunused_tagcat name:>:
<:eif
:><:iterator begin dynunused_tags:> <:dynunused_tag val:> (<:dynunused_tag count:>)
<:iterator end dynunused_tags:><:iterator end dynunused_tagcats :>
TEMPLATE
Size:
 Large (1)
 Medium (1)
 Small (1)

EXPECTED

dyn_template_test "unused tags unfiltered", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynunused_tagcats dynallprods tags: "" :><:
ifDynunused_tagcat nocat:><:or:><:
dynunused_tagcat name:>:
<:eif
:><:iterator begin dynunused_tags:> <:dynunused_tag val:> (<:dynunused_tag count:>)
<:iterator end dynunused_tags:><:iterator end dynunused_tagcats :>
TEMPLATE
 ABC (2)
 XYZ (1)
Colour:
 Black (1)
 Blue (3)
 Green (3)
 Purple (1)
 Red (3)
Size:
 Large (3)
 Medium (4)
 Small (3)

EXPECTED

dyn_template_test "unused tags cat filtered", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynunused_tagcats dynallprods category:"Colour" tags: "" :><:
ifDynunused_tagcat nocat:><:or:><:
dynunused_tagcat name:>:
<:eif
:><:iterator begin dynunused_tags:> <:dynunused_tag val:> (<:dynunused_tag count:>)
<:iterator end dynunused_tags:><:iterator end dynunused_tagcats :>
TEMPLATE
Colour:
 Black (1)
 Blue (3)
 Green (3)
 Purple (1)
 Red (3)

EXPECTED

dyn_template_test "unused tags new style", $parent, <<TEMPLATE, <<EXPECTED;
<:.set ptags = dynarticle.collection_with_tags(
  "all_visible_products",
  [],
  {
    "noobjects":1
  }
  ) -:>
<:# = bse.dumper(ptags) -:>
<:.set ptagcats = bse.categorize_tags(ptags.extratags, [],
  {
   "onlycat":"Colour",
   "counts":ptags.counts
  }) -:>
<:.for cat in ptagcats -:>
<:= cat.name:>:
<:.for val in cat.vals -:>
<:= " " _ val.val :> (<:= val.count :>)
<:.end for-:>
<:.end for:>
TEMPLATE
Colour:
 Black (1)
 Blue (3)
 Green (3)
 Purple (1)
 Red (3)

EXPECTED

dyn_template_test "dyntags", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dyntags "Size:  Small/Colour: Red/XYZ" :><:
dyntag name:>|<:dyntag cat:>|<:dyntag val:>|
<:iterator end dyntags :>
<:iterator begin dyntags [lcgi test5] :><:
dyntag name:>|<:dyntag cat:>|<:dyntag val:>|
<:iterator end dyntags :>
<:iterator begin dyntags [lcgi test6] :><:
dyntag name:>|<:dyntag cat:>|<:dyntag val:>|
<:iterator end dyntags :>
TEMPLATE
Size: Small|Size|Small|
Colour: Red|Colour|Red|
XYZ||XYZ|

Size: Medium|Size|Medium|
Colour: Red|Colour|Red|
Style: Pretty|Style|Pretty|

Size: Medium|Size|Medium|
Colour: Red|Colour|Red|

EXPECTED

dyn_template_test "dynallcats", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallcats:><:
dynallcat id:>
<:iterator end dynallcats:>
TEMPLATE
$parent2->{id}
$parent3->{id}

EXPECTED

dyn_template_test "empty dyncart", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dyncart:><:
dyncartitem title:> <:money dyncartitem price:>
<:iterator end dyncart:>
Total: <:money dyncarttotalcost:>
TEMPLATE

Total: 0.00
EXPECTED

# fake an item in the cart
$req->session->{cart} =
  [
   {
    productId => $prods{prod3}{id},
    units => 1,
    price => scalar $prods{prod3}->price(),
    title => scalar $prods{prod3}->title,
   }
  ];

dyn_template_test "nonempty dyncart", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dyncart:><:
dyncartitem title:> <:money dyncartitem price:>
<:iterator end dyncart:>
Total: <:money dyncarttotalcost:>
TEMPLATE
prod3 20.00

Total: 20.00
EXPECTED

dyn_template_test "cgi", $parent, <<TEMPLATE, <<EXPECTED;
><:cgi unknown:><
><:cgi test1:><
><:cgi test2:><
TEMPLATE
><
>one<
>two three<
EXPECTED

dyn_template_test "lcgi", $parent, <<TEMPLATE, <<EXPECTED;
><:lcgi unknown:><
><:lcgi test1:><
><:lcgi test2:><
><:lcgi "," test1:><
><:lcgi "," test2:><
><:lcgi ")(" test2:><
TEMPLATE
><
>one<
>two/three<
>one<
>two,three<
>two)(three<
EXPECTED

dyn_template_test "deltag", $parent, <<TEMPLATE, <<EXPECTED;
><:deltag "Size: Medium" [lcgi test4]:><
><:deltag "Size:Medium" [lcgi test4]:><
><:deltag "Size:Medium/Colour:Red" [lcgi test5]:><
><:deltag "Size:Medium" [lcgi test5]:><
<:iterator begin dyntags [lcgi test5]
:><:dyntag name:> - <:deltag [dyntag name] [lcgi test5]:>
<:iterator end dyntags:>
TEMPLATE
>Colour: Red<
>Colour: Red<
>Style: Pretty<
>Colour: Red/Style: Pretty<
Size: Medium - Colour: Red/Style: Pretty
Colour: Red - Size: Medium/Style: Pretty
Style: Pretty - Size: Medium/Colour: Red

EXPECTED

dyn_template_test "ifTagIn", $parent, <<TEMPLATE, <<EXPECTED;
<:ifTagIn "Size:medium" [lcgi test5]:>1<:or:>0<:eif:>
<:ifTagIn "Size: Huge" [lcgi test5]:>1<:or:>0<:eif:>
<:ifTagIn "Size: Medium" [lcgi test5]:>1<:or:>0<:eif:>
<:ifTagIn "DEF" [lcgi test5]:>1<:or:>0<:eif:>
TEMPLATE
1
0
1
0
EXPECTED

dyn_template_test "paged default", $parent, <<TEMPLATE, <<EXPECTED;
<:iterator begin dynallprods paged: :><:iterator end dynallprods:>
Current page: <:dynallprods_page:>
Page count: <:dynallprods_pagecount:>
Next page: <:dynallprods_nextpage:>
Previous page: <:dynallprods_prevpage:>
Total count: <:dynallprod_totalcount:>
Count: <:dynallprod_count paged: :>
First number this page: <:dynallprods_firstnumber:>
Last number this page: <:dynallprods_lastnumber:>
Perpage: <:dynallprods_perpage:>
Pages: <:iterator begin dynallprods_pagec
:><:dynallprod_pagec page
:><:ifDynallprod_pagec current:>c<:or:><:eif
:><:ifDynallprod_pagec first:>f<:or:><:eif
:><:ifDynallprod_pagec last:>l<:or:><:eif
:><:ifDynallprod_pagec next:>n<:dynallprod_pagec next:><:or:><:eif
:><:ifDynallprod_pagec prev:>p<:dynallprod_pagec prev:><:or:><:eif:> <:iterator end dynallprods_pagec
:>
<:iterator begin dynallprods paged:
:><:dynallprod_number:> <:dynallprod title:>
<:iterator end dynallprods:>
TEMPLATE

Current page: 2
Page count: 3
Next page: 3
Previous page: 1
Total count: 11
Count: 5
First number this page: 6
Last number this page: 10
Perpage: 5
Pages: 1fn2 2cn3p1 3lp2 
6 prod6
7 prod5
8 prod4
9 prod3
10 prod2

EXPECTED

$prod4->remove($cfg);
for my $prod (@prods) {
  $prod->remove($cfg);
}
$parent3->remove($cfg);
$parent2->remove($cfg);
$parent->remove($cfg);

# produces three test results
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
