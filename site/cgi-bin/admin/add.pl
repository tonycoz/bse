#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = ':0'; }


use strict;
use lib '../modules';
use Constants qw(:edit);

use Articles;
use Article;
use Images;
use Image;
use Squirrel::Template;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use CGI::Cookie;
use Apache::Session::MySQL;
use DatabaseHandle;
use Carp 'verbose';
use Squirrel::ImageEditor;

# session management
# this means all the cookies are handled here
# means we only send one cookie to the user too
my %cookies = fetch CGI::Cookie;
my $sessionid;
$sessionid = $cookies{sessionid}->value if exists $cookies{sessionid};
my %session;

my $dh = single DatabaseHandle;
eval {
  tie %session, 'Apache::Session::MySQL', $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
};
if ($@ && $@ =~ /Object does not exist/) {
  # try again
  undef $sessionid;
  tie %session, 'Apache::Session::MySQL', $sessionid,
    {
     Handle=>$dh->{dbh},
     LockHandle=>$dh->{dbh}
    };
}
unless ($sessionid) {
  # save the new sessionid
  print "Set-Cookie: ",CGI::Cookie->new(-name=>'sessionid', -value=>$session{_session_id}),"\n";
}

# this shouldn't be necessary, but it stopped working and this fixed it
# <sigh>
END {
  untie %session;
}

use Constants qw(%LEVEL_DEFAULTS $SHOPID $PRODUCTPARENT $LINK_TITLES);
my %levels = %LEVEL_DEFAULTS;

my %level_cache;

# what to do
my %steps =
  (
   save=>\&save,
   remove=>\&remove,
  );

my $level = param('level') || 3;

my $articles = Articles->new;
my $article;
my $id = param('id');

my %acts;

my $imageEditor = Squirrel::ImageEditor->new(session=>\%session, 
					     extras=>\%acts,
					     keep=>[ 'id', 'level' ]);

if (defined $id && $id) {
  if ($id != -1) {
    $article = $articles->getByPkey($id);
    if ($article) {
      $level = $article->{level};
      # get the image state
      if (!$session{imagesid} || $session{imagesid} != $id) {
        my @images = Images->getBy('articleId', $article->{id});
        for my $image (@images) {
          # make a new hash rather than just using the object - we will be
          # doing non-OO things to it (like saving them in a session)
	$image = { map { $_=>$image->{$_} } $image->columns };
      }
        $imageEditor->set(\@images, $article->{imagePos});
        $session{imagesid} = $id;
      }
    }
  }
  else {
    # dummy parent to sections
    my @columns = Article->columns;
    @$article{@columns} = ('') x @columns;
    $article->{listed} = 1;
    $article->{id} = -1;
    $article->{parentid} = undef;
    $article->{level} = 0;
    $level = 0;
  }
}
if (!$article) {
  # dummy article
  my @columns = Article->columns;
  @$article{@columns} = ('') x @columns;
  $article->{listed} = 1;
  $article->{body} = '<maximum of 64Kb>';

  # allows a button to add to this section/subsection/article
  if (defined(my $parentid = param('parentid'))) {
    if ($parentid != -1) {
      my $parent = $articles->getByPkey($parentid);
      if ($parent) {
        $level = $parent->{level}+1;
        $article->{parentid} = $parentid;
      }
    }
    else {
      $level = 1;
      $article->{parentid} = -1;
    }
  }
  if (!exists $session{imagesid} || $session{imagesid}) {
    # the images are from editing some article - don't use them
    $session{imagesid} = '';
    $imageEditor->set([], 'tr');
  }
}

my @images;
my $message = ''; # for displaying error message
my @children;
if (defined $id) {
  @children = sort { #$b->{listed} <=> $a->{listed} ||
     $b->{displayOrder} <=> $a->{displayOrder} }
    $articles->children($id);
}
my @title_images;
if (opendir TITLE_IMAGES, "$IMAGEDIR/titles") {
  push(@title_images, 
       grep -f "$IMAGEDIR/titles/$_" && /\.(gif|jpeg|jpg)$/i, 
       readdir TITLE_IMAGES);
  closedir TITLE_IMAGES;
}

my @templates;
if ($article->{parentid} && $article->{parentid} == $SHOPID) {
  @templates = @{$levels{catalog}{templates}}
    if $levels{catalog}{templates};
  if (opendir CAT_TEMPL, "$TMPLDIR/catalog") {
    push(@templates, map "catalog/$_", 
         grep -f "$TMPLDIR/catalog/$_" && /\.tmpl/i, readdir SECT_TEMPL);
    closedir CAT_TEMPL;
  }
  push(@templates, "catalog.tmpl")
    if $article->{parentid} && $article->{parentid} == $SHOPID 
      && -e "$TMPLDIR/catalog.tmpl";
}
else {
  # build a list of templates
  @templates = [ @{$levels{$level}{templates}} ]
    if $levels{$level}{templates};
  for my $where ($level, 'common') {
    if (opendir SECT_TEMPL, "$TMPLDIR/$where") {
      push(@templates, map { "$where/$_" } 
           grep -f "$TMPLDIR/$where/$_" && /\.tmpl$/i, readdir SECT_TEMPL);
      closedir SECT_TEMPL;
    }
  }

  if ($id) {
    # allow special templates for the index
    push(@templates, "index.tmpl") 
      if $id == 1 && -e "$TMPLDIR/index.tmpl";
    push(@templates, "index2.tmpl") 
      if $id == 2 && -e "$TMPLDIR/index2.tmpl";

    # allow special templates for the shop
    push(@templates, "shop_sect.tmpl")
      if $id == $SHOPID && -e "$TMPLDIR/shop_sect.tmpl";
  }
}

unless ($level_cache{$level}{edit}) {
  my $checkfor = "admin/edit_$level";
  $level_cache{$level}{edit} = -e "$TMPLDIR/${checkfor}.tmpl" ? $checkfor :
    $levels{$level}{edit};
}

my $child_index = -1;
%acts =
  (
   #iterate_image=>\&iterate_image,
   image=>\&image,
   article=>\&article,
   articleType => sub { $levels{$level}{display} },
   parentType=> sub { $levels{$level-1}{display} },
   ifart=> sub { $level == 3 },
   ifnew=> sub { !defined $article || !defined $article->{id} || !length $article->{id}},
   list=>\&list,
   #imgtype => sub { $imgtype },
   script=>sub { $ENV{SCRIPT_NAME} },
   level => sub { $level },
   checked => \&checked,
   iterate_images => \&image_iterator,
   message => sub { $message },
   
   # maintain the children (articles/responses)
   iterate_children =>
   sub {
     return ++$child_index < @children;
   },
   child =>
   sub {
     return CGI::escapeHTML($children[$child_index]{$_[0]});
   },
   ifchildren=>sub { scalar @children },
   ifNextChild => sub { $child_index < $#children },
   ifPrevChild => sub { $child_index > 0 },
   iflisted => 
   sub {
     return $acts{$_[0]}->('listed');
   },
   childtype => sub { $levels{$level+1}{display} },
   ifHaveChildType => sub { exists $levels{$level+1} },
   is => sub {
     my ($func, $args) = split ' ', $_[0], 2;
     return $acts{$func}->($args) ? "Yes" : "No";
   },
   templates=>
   sub {
     return popup_menu(-name=>'template', -values=>\@templates,
                       -default=>$id?$article->{template}:$levels{$level}{template});
   },
   titleImages=>
   sub {
     return popup_menu(-name=>'titleImage', -values=>[ '', @title_images ],
                       -labels=>{ ''=>'None', map { $_, $_ } @title_images },
                       -default=>$id?$article->{titleImage} : '',
                       -override);
   },
   editParent =>
   sub {
     if ($id && $id != -1) {
       return <<HTML;
<a href="$ENV{SCRIPT_NAME}?id=$article->{parentid}">Edit parent</a> |
HTML
     }
     else {
       return '';
     }
   },
   edit => \&edit_link,
   adminMenu => sub { $ROOT_URI . "admin/"; },
  );

if ($imageEditor->action($CGI::Q)) {
  exit;
}

for my $step (keys %steps) {
  if (defined param($step)) {
    $steps{$step}->();
    exit;
  }
}

start();

# the startup page for a new article/subsection
sub start {
  # just substitute empty defaults into the blank page
  if ($article->{parentid} && $article->{parentid} == $SHOPID) {
    page('admin/edit_catalog.tmpl');
  }
  else {
    page($level_cache{$level}{edit}.".tmpl");
  }
}

sub save_new_article {
  my %data;
  my @columns = Article->columns;
  use AdminUtil 'save_thumbnail';
  save_thumbnail(undef, \%data);
  for my $name (@columns) {
    $data{$name} = param($name) if defined param($name);
  }
  if ($data{parentid} eq '') {
    $message = "You need to select a valid section";
    start();
    exit;
  }
  
  if (exists $data{template} &&
      $data{template} =~ m#\.\.#) {
    $message = "Please only select templates from the list provided";
    start();
    exit;
  }
 
  my $parent = $articles->getByPkey($data{parentid});
  $data{displayOrder} ||= time;
  $data{titleImage} ||= '';
  $data{imagePos} = $imageEditor->imagePos();
  $data{release} = sql_date($data{release}) || epoch_to_sql(time);
  $data{expire} = sql_date($data{expire}) || $D_99;
  $data{template} ||= $levels{$level}{template};
  $data{link} ||= '';
  $data{admin} ||= '';
  if ($parent) {
    $data{threshold} = $parent->{threshold}
      if !defined $data{threshold} || $data{threshold} =~ /^\s*$/;
    $data{summaryLength} = $parent->{summaryLength}
      if !defined $data{summaryLength} || $data{summaryLength} =~ /^\s*$/;
  }
  else {
    $data{threshold} = $levels{$level}{template}
      if !defined $data{threshold} || $data{threshold} =~ /^\s*$/;
    $data{summaryLength} = 200
      if !defined $data{summaryLength} || $data{summaryLength} =~ /^\s*$/;
  }
  $data{generator} = $data{parentid} == $SHOPID 
    ? 'Generate::Catalog' : 'Generate::Article';
  $data{lastModified} = epoch_to_sql(time);

  shift @columns;
  my $article = $articles->add(@data{@columns});

  # we now have an id - generate the links
  my $link;
  if ($data{generator} eq 'Generate::Article') {
    $link = "$ARTICLE_URI/$article->{id}.html";
    if ($LINK_TITLES) {
      (my $extra = lc $article->{title}) =~ tr/a-z0-9/_/sc;
      $link .= "/".$extra;
    }
    $article->setAdmin("$CGI_URI/admin/admin.pl?id=$article->{id}");
  }
  else {
    $link = $SECURLBASE.$SHOP_URI."/shop$article->{id}.html";
    $article->setAdmin($CGI_URI."/admin/shopadmin.pl");
  }
  $article->setLink($link);
  $article->save();

  # save the images
  my @images = $imageEditor->images();
  for my $image (@images) {
    my $obj = Images->add($article->{id}, @$image{qw/image alt width height/});
  }
  $imageEditor->clear();
  delete $session{imagesid};

  return $article;
}

sub save_old_article {
  for my $name ($article->columns) {
    $article->{$name} = param($name) 
      if defined(param($name)) and $name ne 'id' && $name ne 'parentid';
  }
  if (exists $article->{template} &&
      $article->{template} =~ m#\.\.#) {
    $message = "Please only select templates from the list provided";
    start();
    exit;
  }

  # reparenting
  my $newparentid = param('parentid');
  if ($newparentid == $article->{parentid}) {
    # nothing to do
  }
  elsif ($newparentid != -1) {
    my $newparent = $articles->getByPkey($newparentid);
    if ($newparent) {
      if ($newparent->{level} != $article->{level}-1) {
	# the article cannot become a child of itself or one of it's 
	# children
	if ($id == $newparentid 
	    || is_descendant($article->{id}, $newparentid)) {
	  $message = "Cannot become a child of itself or of a descendant";
	  start();
	  exit;
	}
	if (is_descendant($article->{id}, $SHOPID)) {
	  $message = "Cannot become a descendant of the shop";
	  start();
	  exit;
	}
	reparent($article, $newparentid);
      }
      else {
	# stays at the same level, nothing special
	$article->{parentid} = $newparentid;
      }
    }
    # else ignore it
  }
  else {
    # becoming a section
    reparent($article, -1);
  }

  
  $article->{imagePos} = $imageEditor->imagePos();
  $article->{listed} = param('listed');
  $article->{release} = sql_date(param('release')) || $D_00;
  $article->{expire} = sql_date(param('expire')) || $D_99;
  $article->{lastModified} =  epoch_to_sql(time);
  if ($article->{id} != 1 && $article->{link} && $LINK_TITLES) {
    (my $extra = lc $article->{title}) =~ tr/a-z0-9/_/sc;
    $article->{link} = "$ARTICLE_URI/$article->{id}.html/$extra";
  }
  use AdminUtil 'save_thumbnail';
  save_thumbnail($article, $article);

  $article->save();

  # save the image list
  my @images = $imageEditor->images();
  my $images = Images->new;
  my %imagefiles = map { $_->{image}, 1 } @images;

  # out with the old
  my @oldimages = $images->getBy('articleId', $id);
  for my $image (@oldimages) {
    unless ($imagefiles{$image->{image}}) {
      # image not used anymore
      unlink "$IMAGEDIR/$image->{image}";
    }
    $image->remove();
  }
  # in with the new
  for my $image (@images) {
    Images->add($article->{id}, @$image{qw/image alt width height/});
  }

  $imageEditor->clear();
  delete $session{imagesid};
}

# saves the article and it's image list
sub save {
  if (defined $article->{id} and length $article->{id}) {
    save_old_article();
  }
  else {
    $article = save_new_article();
  }

  use Util 'generate_article';
  generate_article($articles, $article) if $AUTO_GENERATE;

  print "Refresh: 0; url=\"$URLBASE$article->{admin}\"\n";
  print "Content-type: text/html\n\n<HTML></HTML>\n";
}

sub remove {
  my $deleteid = param('deleteid');
  if (defined $deleteid) {
    # you can't delete an article with children
    if ($articles->children($deleteid)) {
      $message = "This article has children.  You must delete the children first (or change their parents)";
    }
    if (grep ($_ == $deleteid, @NO_DELETE )) {
      $message = "Sorry, these pages are essential to the site structure - they cannot be deleted";
    }
    my $delart = $articles->getByPkey($deleteid);
    if ($delart->{generator} eq 'Generate::Product' ) {
      $message = "Sorry, you can only delete articles, not products";
    }
    if ($deleteid == $SHOPID) {
      $message = "Sorry, these pages are essential to the store - they cannot be deleted - you may want to hide the the store instead.";
    }
    if ($message) {
      start();
      exit;
    }

    # first lose the images
    my @images = Images->getBy(articleId=>$deleteid);
    for my $image (@images) {
      unlink("$IMAGEDIR/$image->{image}");
      $image->remove();
    }
    
    $delart->remove();
    $articles = Articles->new(1);
    use Util 'generate_article';
    generate_article($articles, $article) if $AUTO_GENERATE;
    @children = grep { $_->{id} != $deleteid } @children;
    start();
  }
}

sub page {
  my ($page) = @_;
  print header, Squirrel::Template->new->show_page($TMPLDIR, $page, \%acts);
}

sub article {
  my ($name) = @_;
  return display_date($article->{$name}) || ''
    if $name eq 'expire' || $name eq 'release';
  return CGI::escapeHTML($article->{$name});
}


sub list {
  my $what = shift;

  if ($what eq 'listed') {
    my @values = qw(0 1);
    my %labels = ( 0=>"No", 1=>"Yes");
    if ($level <= 2) {
      $labels{2} = "In Sections, but not menu";
      push(@values, 2);
    }
    else {
      $labels{2} = "In content, but not menus";
      push(@values, 2);
    }
    return popup_menu(-name=>'listed',
		      -values=>\@values,
		      -labels=>\%labels,
		      -default=>$article->{listed});
  }
  else {
    # articles that this article could become a child of
    my @parents = $articles->getBy('level', $level-1);
    @parents = grep { $_->{generator} eq 'Generate::Article' 
                    && $_->{id} != $SHOPID } @parents;

    
    my $values = [ map {$_->{id}} @parents ];
    my $labels = { map { $_->{id} => "$_->{title} ($_->{id})" } @parents };

    if ($level == 1) {
      push @$values, -1;
      $labels->{-1} = "No parent - this is a section";
    }
    
    if ($id && reparent_updown()) {
      # we also list the siblings and grandparent (if any)
      my @siblings = grep $_->{id} != $id && $_->{id} != $SHOPID,
	$articles->getBy(parentid => $article->{parentid});
      push @$values, map $_->{id}, @siblings;
      @$labels{map $_->{id}, @siblings} =
	map { "-- move down a level -- $_->{title} ($_->{id})" } @siblings;

      if ($article->{parentid} != -1) {
	my $parent = $articles->getByPkey($article->{parentid});
	if ($parent->{parentid} != -1) {
	  my $gparent = $articles->getByPkey($parent->{parentid});
	  push @$values, $gparent->{id};
	  $labels->{$gparent->{id}} =
	    "-- move up a level -- $gparent->{title} ($gparent->{id})";
	}
	else {
	  push @$values, -1;
	  $labels->{-1} = "-- move up a level -- become a section";
	}
      }
    }
    my $html;
    if (defined $article->{parentid}) {
      $html = popup_menu(-name=>'parentid',
			 -values=> $values,
			 -labels => $labels,
			 -default => $article->{parentid},
			 -override=>1);
    }
    else {
      $html = popup_menu(-name=>'parentid',
			 -values=> $values,
			 -labels => $labels,
			 -override=>1);
    }

    # munge the html - we display a default value, so we need to wrap the 
    # default <select /> around this one
    $html =~ s!^<select[^>]+>|</select>!!gi;
    return $html;
  }
}

sub edit_link {
  my ($args) = @_;
  my ($which, $name) = split / /, $args, 2;
  $name ||= 'Edit';
  my $gen_class;
  if ($acts{$which} && ($gen_class = $acts{$which}->('generator'))) {
    eval "use $gen_class";
    unless ($@) {
      my $gen = $gen_class->new;
      my $link = $gen->edit_link($acts{$which}->('id'));
      return qq!<a href="$link">$name</a>!;
    }
  }
  return '';
}

sub checked {
  my ($func, $name, $value) = split ' ', $_[0];
  return $acts{$func}->($name) eq $value ? 'checked' : ''
}

# image iteration

{
  my $image;
  my @iter_images;
  
  # used to iterate over images in the article editor
  # maybe these should be combined
  sub image_iterator {
    my ($ignore, $name) = @_;
    if (!$image) {
      @iter_images = $imageEditor->images();
    }
    $image = shift @iter_images;
    return $image;
  }
  
  sub image {
    return $image->{$_[0]};
  }
}

# convert a user entered date from dd/mm/yyyy to ANSI sql format
# we try to parse flexibly here
sub sql_date {
  my $str = shift;
  my ($year, $month, $day);

  # look for a date
  if (($day, $month, $year) = ($str =~ m!(\d+)/(\d+)/(\d+)!)) {
    $year += 2000 if $year < 100;

    return sprintf("%04d-%02d-%02d", $year, $month, $day);
  }
  return undef;
}

# convert a data from ANSI sql format to .au format
sub display_date {
  my ($date) = @_;
  
  if ( my ($year, $month, $day) = 
       ($date =~ /^(\d+)-(\d+)-(\d+)/)) {
    return sprintf("%02d/%02d/%04d", $day, $month, $year);
  }
  return undef;
}

# convert an epoch time to sql format
sub epoch_to_sql {
  use POSIX 'strftime';
  my ($time) = @_;

  return strftime('%Y-%m-%d', localtime $time);
}

# can the user reparent to a different level?
sub reparent_updown {
  if (ref $REPARENT_UPDOWN) {
    return $REPARENT_UPDOWN->();
  }
  else {
    return $REPARENT_UPDOWN;
  }
}

# tests if $desc is a descendant of $art
# where both are article ids
sub is_descendant {
  my ($art, $desc) = @_;
  
  my @check = ($art);
  while (@check) {
    my $parent = shift @check;
    $parent == $desc and return 1;
    my @kids = $articles->getBy(parentid=>$parent);
    push @check, map $_->{id}, @kids;
  }

  return 0;
}

# reparent an article
# this includes fixing the level number of the article's children
sub reparent {
  my ($article, $newparentid) = @_;

  my $newlevel;
  if ($newparentid == -1) {
    $newlevel = 1;
  }
  else {
    my $parent = $articles->getByPkey($newparentid);
    unless ($parent) {
      $message = "Cannot get new parent article";
      start();
      exit;
    }
    $newlevel = $parent->{level} + 1;
  }
  # the caller will save this one
  $article->{parentid} = $newparentid;
  $article->{level} = $newlevel;
  $article->{displayOrder} = time;

  my @change = ( [ $article->{id}, $newlevel ] );
  while (@change) {
    my $this = shift @change;
    my ($art, $level) = @$this;

    my @kids = $articles->getBy(parentid=>$art);
    push @change, map { [ $_->{id}, $level+1 ] } @kids;

    for my $kid (@kids) {
      $kid->{level} = $level+1;
      $kid->save;
    }
  }
}

__END__

=head1 NAME

add.pl - article editing tool

=head1 SYNOPSYS

A CGI script.

=head1 DESCRIPTION

add.pl is used to add and edit articles.

=head1 TAGS

=over 4

=item edit I<which> I<label>

Inserts a link to a page to edit the specified article.

=back

=cut
