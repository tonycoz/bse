#!/usr/bin/perl -w
use strict;
use lib '../modules';
use Articles;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use Constants qw($URLBASE);
use Util qw(generate_button);

my $articles = Articles->new;
  my $id = param('id');
if (generate_button()) {
  if (defined $id) {
    use Util 'generate_article';
    my $article = $articles->getByPkey($id)
      or die "No such article $id found";
    generate_article($articles, $article);
  }
  else {
    use Util 'generate_all';
    generate_all($articles);
  }
}

my $fromid = param('fromid') || $id;
my $baseurl;
if (defined $fromid
    and my $fromart = $articles->getByPkey($fromid)) {
  $baseurl = $fromart->{admin};
}
else {
  $baseurl = "/admin/";
}

print "Refresh: 0; url=\"$URLBASE$baseurl\"\n";
print "Content-type: text/html\n\n<HTML></HTML>\n";
