#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use CGI qw(:standard);
use Constants;
use Util qw(generate_button regen_and_refresh);
use BSE::WebUtil qw(refresh_to_admin);
use Carp 'verbose';
use BSE::Request;
use URI::Escape;

my $req = BSE::Request->new;

my $cfg = $req->cfg;
my $cgi = $req->cgi;
my $siteurl = $cfg->entryErr('site', 'url');
unless ($req->check_admin_logon()) {
  refresh_to_admin($cfg, "/cgi-bin/admin/logon.pl");
  exit;
}

my $id = $cgi->param('id');
my $fromid = $cgi->param('fromid') || $id;
my $baseurl;
if (defined $fromid
    and my $fromart = Articles->getByPkey($fromid)) {
  $baseurl = $fromart->{admin};
}
else {
  $baseurl = "/cgi-bin/admin/menu.pl";
}

if (generate_button()) {
  my $callback;
  my $progress = $cgi->param('progress');
  if ($progress) {
    $| = 1;
    print "Content-Type: text/html\n\n";
    print "<html><title>Regenerating your site</title></head><body>";
    print "<h2>Regenerating your site</h2>\n";
    $callback = sub { print "<div>",CGI::escapeHTML($_[0]),"</div>" };
  }
  if (defined $id) {
    use Util 'generate_article';
    my $article;
    my $can;
    if ($id eq 'extras') {
      $article = 'extras';
      $can = $req->user_can('regen_extras');
    }
    else {
      $article = Articles->getByPkey($id)
	or die "No such article $id found";
      $can = $req->user_can('regen_article', $article);
    }
    if ($can) {
      regen_and_refresh('Articles', $article, 1, 
			$siteurl . $baseurl, $cfg, $callback);
    }
    else {
      if ($progress) {
	print "<p>You don't have permission to regenerate that</p>\n";
      }
      else {
	if ($baseurl =~ /menu\.pl$/) {
	  $baseurl .= "?m=".uri_escape("You don't have permission to regenerate that");
	}
	refresh_to_admin($cfg, $baseurl);
      }
    }
  }
  else {
    if ($req->user_can('regen_all')) {
      regen_and_refresh('Articles', undef, 1, 
			$baseurl, $cfg, $callback);
    }
    else {
      if ($progress) {
	print "<p>You don't have permission to regenerate all</p>\n";
      }
      else {
	if ($baseurl =~ /menu\.pl$/) {
	  $baseurl .= "?m=".uri_escape("You don't have permission to regenerate all");
	}
	refresh_to_admin($cfg, $baseurl);
      }
    }
  }
  if ($progress) {
    print qq!<p>Done <a href="/cgi-bin/admin/menu.pl">Return to admin menu</a></p>\n!;
    print "</body></html>\n";
  }
}
else {
  refresh_to("$siteurl$baseurl");
}

exit;
