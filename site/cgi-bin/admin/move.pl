#!/usr/bin/perl -w

# reorders the article then refreshes back to the parent

use strict;
use lib '../modules';
use Articles;
use CGI ':standard';
use Carp 'verbose';
use CGI::Carp 'fatalsToBrowser';
use Constants qw($URLBASE);

my $id = param('id');
my $direction = param('d');

my $articles = Articles->new;

my $article = $articles->getByPkey($id)
  or die "Could not find article $id";

# get our siblings, in order
my @siblings;
if (param('all')) {
  @siblings = sort { $b->{displayOrder} <=> $a->{displayOrder} }
		       $articles->children($article->{parentid});
}
else {
  @siblings = $articles->listedChildren($article->{parentid});
}

# find our article
my $index;
for ($index = 0; $index < @siblings; ++$index) {
  last if $siblings[$index]{id} == $id;
}

die "This program is broken - couldn't find self in list of parents children"
  if $index == @siblings;

if ($direction eq 'down') {
  die "There is no next article to swap with"
    if $index == $#siblings;
  ($article->{displayOrder}, $siblings[$index+1]{displayOrder})
    = ($siblings[$index+1]{displayOrder}, $article->{displayOrder});
  $siblings[$index+1]->save();
}
elsif ($direction eq 'up') {
  die "There is no previous article to swap with"
    if $index == 0;
  ($article->{displayOrder}, $siblings[$index-1]{displayOrder})
    = ($siblings[$index-1]{displayOrder}, $article->{displayOrder});
  $siblings[$index-1]->save();
  
}
else {
  die "Sorry, can't move articles sideways";
}

$article->save();
use Util 'generate_article';
generate_article('Articles', $article);


if (param('refreshto')) {
  print "Refresh: 0; url=\"$URLBASE",param('refreshto'),"\"\n";
}
elsif (param('edit')) {
  # refresh back to editor
  print "Refresh: 0; url=\"$URLBASE/cgi-bin/admin/add.pl?id=$article->{parentid}#children\"\n";
}
else {
  # refresh back to the parent
  my $parent = $articles->getByPkey($article->{parentid});
  print "Refresh: 0; url=\"$URLBASE$parent->{admin}\"\n";
}
print "Content-Type: text/html\n\n<html></html>\n";
