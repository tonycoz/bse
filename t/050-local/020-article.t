#!perl -w
use strict;
use Test::More tests => 16;
use BSE::Test ();
use File::Spec;
use BSE::Cfg;

use_ok("Article");

{
  my $cfg = BSE::Cfg->new_from_text(text => <<'EOS');
[paths]
base=/test
public_html=$(base)/htdocs
EOS

  is(Article->link_to_filename($cfg, "/"), "/test/htdocs/index.html",
     "check default link to /");
  is(Article->link_to_filename($cfg, "/foo.html/test"), "/test/htdocs/foo.html",
     "check default link to filename - trailing title");
  is(Article->link_to_filename($cfg, "/test.html"), "/test/htdocs/test.html",
     "check default link to filename - trailing filename");
  is(Article->link_to_filename($cfg, "//test.html"), "/test/htdocs/test.html",
     "check default link to filename - doubled /");
}

{
  my $cfg = BSE::Cfg->new_from_text(text => <<'EOS');
[paths]
base=/test
public_html=$(base)/htdocs

[basic]
index_file=default.htm
EOS

  is(Article->link_to_filename($cfg, "/"), "/test/htdocs/default.htm",
     "check cfg link to filename");
}

{
  my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
  
  use_ok("BSE::API");
  
  BSE::API::bse_init($base_cgi);
  my $cfg = BSE::API::bse_cfg();

  {
    my $now = time;
    use POSIX qw(strftime);
    my $today = strftime("%Y-%m-%d", localtime $now);
    my $yesterday = strftime("%Y-%m-%d", localtime($now - 86_400));
    my $tomorrow = strftime("%Y-%m-%d", localtime($now + 86_400));
    my $tomorrow2 = strftime("%Y-%m-%d", localtime($now + 2*86_400));
    my $art = BSE::API::bse_make_article
      (
       cfg => $cfg,
       title => "t16article.t",
       release => $today,
       expire => $tomorrow,
      );
    ok($art, "make an article");
    ok($art->is_released, "check successful is released");
    ok(!$art->is_expired, "check false is expired");
    $art->set_release($tomorrow);
    ok(!$art->is_released, "check false is released");
    $art->set_expire($yesterday);
    ok($art->is_expired, "check true is expired");

    # add some images
    my $im1 = BSE::API::bse_add_image($cfg, $art,
				      file => "t/data/t101.jpg");
    $im1->set_tags([ "abc" ]);
    ok($im1, "add first image");
    my $im2 = BSE::API::bse_add_image($cfg, $art,
				      file => "t/data/govhouse.jpg");
    ok($im2, "add second image");
    my $tagged = $art->images_tagged([ "ABC" ]);
    ok($tagged && @$tagged, "found a tagged image");
    is($tagged->[0]->id, $im1->id, "found the right image");

    END {
      $art->remove($cfg);
    }
  }
}

