#!perl -w
use strict;
use BSE::Test qw(base_url);
use File::Spec;
use File::Temp;

use Test::More tests => 5;

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

use BSE::Importer;
use BSE::API qw(bse_init bse_make_article);

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
ok(bse_init($base_cgi),   "initialize api")
  or print "# failed to bse_init in $base_cgi\n";

my $when = time;

my $cfg = BSE::Cfg->new(path => $base_cgi, extra_text => <<CFG);
[import profile simple$when]
map_title=1
source=CSV
target=Article

[import profile simpleupdate$when]
map_linkAlias=1
map_body=2
source=CSV
target=Article
update_only=1
sep_char=\\t
CFG

{
  my @added;

  my $imp = BSE::Importer->new(cfg => $cfg, profile => "simple$when", callback => sub { note @_ });
  $imp->process("t/data/importer/article-simple.csv");
  @added = sort { $a->title cmp $b->title } $imp->leaves;

  is(@added, 2, "imported two articles");
  is($added[0]->title, "test1", "check title of first import");
  is($added[1]->title, "test2", "check title of second import");

  END {
    $_->remove($cfg) for @added;
  }
}

{
  my $testa = bse_make_article(cfg => $cfg, title => "test updates",
			       linkAlias => "alias$when");

  my $fh = File::Temp->new;
  my $filename = $fh->filename;
  print $fh <<EOS;
linkAlias\tbody
"alias$when"\t"This is the body text with multiple lines

Yes, multiple lines with CSV!"
EOS
  close $fh;
  my $imp = BSE::Importer->new(cfg => $cfg, profile => "simpleupdate$when", callback => sub { note @_ });
  $imp->process($filename);
  my $testb = Articles->getByPkey($testa->id);
  like($testb->body, qr/This is the body/, "check the body is updated");

  END {
    $testa->remove($cfg) if $testa;
  }
}
