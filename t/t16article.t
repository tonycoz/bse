#!perl -w
use strict;
use Test::More tests => 12;
use BSE::Test ();
use File::Spec;

use_ok("Article");

{
  my $cfg = bless 
    {
     paths =>
     {
      base => "/test",
      public_html => '$(base)/htdocs',
     }
    }, "Test::Cfg";

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
  my $cfg = bless 
    {
     paths =>
     {
      base => "/test",
      public_html => '$(base)/htdocs',
     },
     basic =>
     {
      index_file => "default.htm"
     }
    }, "Test::Cfg";
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

    $art->remove($cfg);
  }
}

package Test::Cfg;

sub entry {
  my ($self, $section, $key, $def) = @_;

  my $sect = $self->{$section}
    or return $def;
  exists $sect->{$key} or return $def;

  return $sect->{$key};
}

sub entryIfVar {
  my ($self, $section, $key, $def) = @_;

  my $value = $self->entry($section, $key);
  defined $value
    or return $def;

  return $self->entryVar($section, $key);
}

sub entryErr {
  my ($self, $section, $key) = @_;

  my $value = $self->entry($section, $key);
  defined $value or die "Missing [$section].$key";

  return $value;
}

sub entryVar {
  my ($self, $section, $key, $depth) = @_;

  $depth ||= 0;
  $depth < 10
    or die "Too many levels of variables getting $key from $section";
  my $value = $self->entryErr($section, $key);
  $value =~ s!\$\(([\w ]+)/([\w ]+)\)! $self->entryVar($1, $2, $depth+1) !eg;
  $value =~ s!\$\(([\w ]+)\)! $self->entryVar($section, $1, $depth+1) !eg;

  $value;
}

sub content_base_path {
  my ($self) = @_;

  return $self->entryVar("paths", "public_html");
}
