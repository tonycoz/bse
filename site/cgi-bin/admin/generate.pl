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

#my $articles = Articles->new;
my $id = param('id');
my $fromid = param('fromid') || $id;
my $baseurl;
if (defined $fromid
    and my $fromart = Articles->getByPkey($fromid)) {
  $baseurl = $fromart->{admin};
}
else {
  $baseurl = "/admin/";
}

my $cfg = BSE::Cfg->new;
my $siteurl = $cfg->entryErr('site', 'url');
if (generate_button()) {
  my $callback;
  if (param('progress')) {
    $| = 1;
    print "Content-Type: text/html\n\n";
    print "<html><title>Regenerating your site</title></head><body>";
    print "<h2>Regenerating your site</h2>\n";
    $callback = sub { print "<div>",CGI::escapeHTML($_[0]),"</div>" };
  }
  if (defined $id) {
    use Util 'generate_article';
    my $article;
    if ($id eq 'extras') {
      $article = 'extras';
    }
    else {
      $article = Articles->getByPkey($id)
	or die "No such article $id found";
    }
    regen_and_refresh('Articles', $article, 1, 
		      $siteurl . $baseurl, $cfg, $callback);
  }
  else {
    regen_and_refresh('Articles', undef, 1, 
		      $siteurl . $baseurl, $cfg, $callback);
  }
  if (param('progress')) {
    print qq!<p>Done <a href="/admin/">Return to admin menu</a></p>\n!;
    print "</body></html>\n";
  }
}
else {
  refresh_to("$siteurl$baseurl");
}

exit;
