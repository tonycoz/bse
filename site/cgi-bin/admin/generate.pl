#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use CGI qw(:standard);
use Constants;
use Util qw(generate_button regen_and_refresh refresh_to);
use Carp 'verbose';
use BSE::Cfg;

my $articles = Articles->new;
my $id = param('id');
my $fromid = param('fromid') || $id;
my $baseurl;
if (defined $fromid
    and my $fromart = $articles->getByPkey($fromid)) {
  $baseurl = $fromart->{admin};
}
else {
  $baseurl = "/admin/";
}

my $cfg = BSE::Cfg->new;
my $siteurl = $cfg->entryErr('site', 'url');
if (generate_button()) {
  if (defined $id) {
    use Util 'generate_article';
    my $article = $articles->getByPkey($id)
      or die "No such article $id found";
    regen_and_refresh($articles, $article, 1, 
		      $siteurl . $baseurl);
  }
  else {
    regen_and_refresh($articles, undef, 1, 
		      $siteurl . $baseurl);
  }
}
else {
  refresh_to("$siteurl$baseurl");
}
