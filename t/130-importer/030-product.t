#!perl -w
use strict;
use BSE::Test qw(base_url);
use File::Spec;
use File::Temp;
use Test::More;

BEGIN {
  eval "require Text::CSV;"
    or plan skip_all => "Text::CSV not available";
}

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

use BSE::Importer;
use BSE::API qw(bse_init bse_make_product);

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
ok(bse_init($base_cgi), "initialize api")
  or print "# failed to bse_init in $base_cgi\n";

my $when = time;

my $cfg = BSE::Cfg->new(path => $base_cgi, extra_text => <<CFG);
[import profile simple$when]
map_title=1
map_retailPrice=2
source=CSV
price_dollar=1

[import profile simpleupdate$when]
map_linkAlias=1
map_body=2
source=CSV
target=Product
update_only=1
sep_char=\\t
code_field=linkAlias

[import profile newdup$when]
map_product_code=1
map_title=2
map_retailPrice=3
skiplines=0
source=CSV
target=Product

[import profile avoidcorrupt$when]
map_id=1
map_articleId=2
map_title=3
map_product_code=4
source=CSV
target=Product
sep_char=\\t
codes=1
code_field=product_code
update_only=1
CFG

{
  my @added;

  my $imp = BSE::Importer->new(cfg => $cfg, profile => "simple$when",
			       callback => sub { note @_ });
  $imp->process("t/data/importer/product-simple.csv");
  @added = sort { $a->title cmp $b->title } $imp->leaves;

  is(@added, 2, "imported two products");
  is($added[0]->title, "test1", "check title of first import");
  is($added[0]->retailPrice, 1000, "check price of first import");
  is($added[1]->title, "test2", "check title of second import");
  is($added[1]->retailPrice, 800, "check price of second import");

  END {
    $_->remove($cfg) for @added;
  }
}

{
  my $testa = bse_make_product
    (
     cfg => $cfg,
     title => "test updates",
     linkAlias => "P$when",
     retailPrice => 500,
     product_code => "C$when",
    );

  $testa->set_prices({ 1 => 400 });

  {
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    print $fh <<EOS;
linkAlias\tbody
"P$when"\t"This is the body text with multiple lines

Yes, multiple lines with CSV!"
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "simpleupdate$when",
				 callback => sub { note @_ });
    $imp->process($filename);
    my $testb = BSE::TB::Articles->getByPkey($testa->id);
    like($testb->body, qr/This is the body/, "check the body is updated");
  }

  { # fail to duplicate a product code
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    my $id = $testa->id;
    print $fh <<EOS;
"C$when",A new title,100
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "newdup$when", callback => sub { note @_ });
    $imp->process($filename);
    is_deeply([ $imp->leaves ], [], "should be no updated articles");
  }

 SKIP:
  {
    my @prices = $testa->prices;
    is(@prices, 1, "should still be a tier price")
      or skip "No prices found", 2;
    is($prices[0]->tier_id, 1, "check tier id");
    is($prices[0]->retailPrice, 400, "check tier price");
  }

  END {
    $testa->remove($cfg) if $testa;
  }
}

{
  my $code = "D$when";
  my $testa = bse_make_product
    (
     cfg => $cfg,
     title => "test updates",
     linkAlias => "P$when",
     retailPrice => 500,
     product_code => $code,
    );
  diag "Product id ".$testa->id;
  {
    my $fh = File::Temp->new;
    my $filename = $fh->filename;

    print $fh <<EOS;
id\tarticleId\ttitle\tproduct_code
1\t2\tTesting\t$code
EOS
    close $fh;
    my $imp = BSE::Importer->new(cfg => $cfg, profile => "avoidcorrupt$when",
				 callback => sub { note @_ });
    $imp->process($filename);
    my $testb = BSE::TB::Products->getByPkey($testa->id);
    ok($testb, "managed to fully load the product");
    is($testb->title, "Testing", "check the title is updated");
    my $top = BSE::TB::Articles->getByPkey(1);
    isnt($top->generator, "BSE::Generate::Product",
	 "make sure we didn't scribble over article 1");
  }

  END {
    $testa->remove($cfg) if $testa;
  }
}

done_testing();
