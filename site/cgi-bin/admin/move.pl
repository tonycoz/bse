#!/usr/bin/perl -w

# reorders the article then refreshes back to the parent

use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use CGI ':standard';
use Carp 'verbose';
use CGI::Carp 'fatalsToBrowser';
use BSE::Request;
use Constants;
use Util 'refresh_to';

my $req = BSE::Request->new;

my $cfg = $req->cfg;
my $cgi = $req->cgi;
my $urlbase = $cfg->entryVar('site', 'url');

unless ($req->check_admin_logon()) {
  refresh_to("$urlbase/cgi-bin/admin/logon.pl");
  exit;
}

my $id = $cgi->param('id');
my $direction = $cgi->param('d');

my $articles = Articles->new;
  
my $article;
if (defined $cgi->param('stepchild')) {
  my $stepchild = $cgi->param('stepchild');
  if ($req->user_can(edit_reorder_stepparents=>$stepchild)) {
    # we always need a swap for this one
    
    my $article = Articles->getByPkey($stepchild)
      or die "Cannot find child $stepchild";
    
    my $other = $cgi->param('other');
    
    require 'OtherParents.pm';
    my $one = OtherParents->getBy(parentId=>$id, childId=>$stepchild)
      or die "Cannot find link between child $stepchild and parent $id";
    my $two = OtherParents->getBy(parentId=>$other, childId=>$stepchild)
      or die "Cannot find link between child $stepchild and parent $other";
    ($one->{childDisplayOrder}, $two->{childDisplayOrder}) =
      ($two->{childDisplayOrder}, $one->{childDisplayOrder});
    $one->save;
    $two->save;
    use Util 'generate_article';
    generate_article('Articles', $article);
  }
}
elsif (defined $cgi->param('stepparent')) {
  require 'OtherParents.pm';

  my $stepparent = $cgi->param('stepparent');
  if ($req->user_can(edit_reorder_children => $stepparent)) {
    my $other = $cgi->param('other');
    my $onename = 'parentDisplayOrder';
    my $one = OtherParents->getBy(parentId=>$stepparent, childId=>$id);
    unless ($one) {
      $onename = 'displayOrder';
      $one = Articles->getByPkey($id)
	or die "Could not find article $id";
    }
    my $twoname = 'parentDisplayOrder';
    my $two = OtherParents->getBy(parentId=>$stepparent, childId=>$other);
    unless ($two) {
      $twoname = 'displayOrder';
      $two = Articles->getByPkey($other)
	or die "Could not find article $other";
    }
    ($one->{$onename}, $two->{$twoname}) = ($two->{$twoname}, $one->{$onename});
    $one->save;
    $two->save;
    use Util 'generate_article';
    generate_article('Articles', $article);
  }
}
else {
  $article = $articles->getByPkey($id)
    or die "Could not find article $id";

  if ($req->user_can(edit_reorder_children => $article->{parentid})) {
    # get our siblings, in order
    my @siblings;
    if ($cgi->param('all')) {
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
    elsif ($direction eq 'swap') {
      my $other = $cgi->param('other')
	or die "Need to specify an 'other' article to swap with";
      my ($other_index) = grep $siblings[$_]{id} == $other, 0..$#siblings;
      defined $other_index or die "No such such sibling";
      
      ($article->{displayOrder}, $siblings[$other_index]{displayOrder})
	= ($siblings[$other_index]{displayOrder}, $article->{displayOrder});
      $siblings[$other_index]->save();
    }
    else {
      die "Sorry, can't move articles sideways";
    }
    
    $article->save();
    use Util 'generate_article';
    generate_article('Articles', $article);
  }
}

if ($cgi->param('refreshto')) {
  refresh_to($urlbase .$cgi->param('refreshto'));
}
elsif ($cgi->param('r')) {
  refresh_to($urlbase .$cgi->param('r'));
}
elsif ($cgi->param('edit')) {
  # refresh back to editor
  refresh_to("$urlbase/cgi-bin/admin/add.pl?id=$article->{parentid}#children");
}
else {
  # refresh back to the parent
  my $parent = $articles->getByPkey($article->{parentid});
  refresh_to("$urlbase$parent->{admin}");
}
