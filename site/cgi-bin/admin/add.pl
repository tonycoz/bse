#!/usr/bin/perl -w

use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Constants qw(:edit $CGI_URI $IMAGES_URI);

use Articles;
use Article;
use Images;
use Image;
use Squirrel::Template;
use CGI qw(:standard);
use CGI::Cookie;
use BSE::DB;
use Carp 'verbose';
use Squirrel::ImageEditor;
use BSE::Cfg;
use BSE::Session;
use BSE::Util::Tags;

my $cfg = BSE::Cfg->new;
my %session;
BSE::Session->tie_it(\%session, $cfg);

my $urlbase = $cfg->entryVar('site', 'url');
my $securlbase = $cfg->entryVar('site', 'secureurl');
use Constants qw(%LEVEL_DEFAULTS $SHOPID $PRODUCTPARENT $LINK_TITLES);
my %levels = %LEVEL_DEFAULTS;

my %level_cache;

# what to do
my %steps =
  (
   save=>\&save,
   remove=>\&remove,
   add_stepkid=>\&add_stepkid,
   del_stepkid=>\&del_stepkid,
   save_stepkids => \&save_stepkids,
   add_stepparent => \&add_stepparent,
   del_stepparent => \&del_stepparent,
   save_stepparents => \&save_stepparents,
  );

my $level = param('level') || 3;

#my $articles = Articles->new;
my $articles = 'Articles';
my $article;
my $id = param('id');

my %acts;

my $imageEditor = Squirrel::ImageEditor->new(session=>\%session, 
					     extras=>\%acts,
					     keep=>[ qw/id level parentid/ ],
					     cfg=>$cfg);

if (defined $id && $id) {
  if ($id != -1) {
    $article = $articles->getByPkey($id);
    if ($article) {
      $level = $article->{level};
      # get the image state
      if (!$session{imagesid} || $session{imagesid} != $id) {
        my @images = sort { $a->{id} <=> $b->{id} }
	  Images->getBy('articleId', $article->{id});
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
    if ($parentid && $parentid != -1) {
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
my $parent;
$parent = $articles->getByPkey($article->{parentid})
  if $article && $article->{parentid} && $article->{parentid} > 0;

my @images;
my $message = param('message') || ''; # for displaying error message
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
if (should_be_catalog($article, $parent, $articles)) {
  @templates = @{$levels{catalog}{templates}}
    if $levels{catalog}{templates};
  if (opendir CAT_TEMPL, "$TMPLDIR/catalog") {
    push(@templates, sort map "catalog/$_", 
         grep -f "$TMPLDIR/catalog/$_" && /\.tmpl/i, readdir CAT_TEMPL);
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
      push(@templates, sort map { "$where/$_" } 
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
my $def_template;
if ($parent && $parent->{id}) {
  my $section = "children of $parent->{id}";
  $def_template = $cfg->entry($section, "template");
  if (my $dirs = $cfg->entry($section, "template_dirs")) {
    for my $dir (split /,/, $dirs) {
      next unless $dir && -d "$TMPLDIR/$dir";
      if (opendir CUST_TEMPL, "$TMPLDIR/$dir") {
	push(@templates, sort map "$dir/$_",
	     grep -f "$TMPLDIR/$dir/$_" && /\.tmpl$/i, readdir CUST_TEMPL);
	closedir CUST_TEMPL;
      }
    }
  }
}

unless ($level_cache{$level}{edit}) {
  my $checkfor = "admin/edit_$level";
  $level_cache{$level}{edit} = -e "$TMPLDIR/${checkfor}.tmpl" ? $checkfor :
    $levels{$level}{edit};
}

my @files;
if ($article->{id} && $article->{id} > 0) {
  require 'ArticleFiles.pm';
  @files = ArticleFiles->getBy(articleId=>$article->{id});
}
my $file_index;

use OtherParents;
my @stepkids = OtherParents->getBy(parentId=>$article->{id}) if $article->{id};
my %stepkids = map { $_->{childId} => $_ } @stepkids;
my @allkids = $article->allkids if $article->{id} && $article->{id} > 0;
my $allkids_index = -1;
my @possibles;
my @stepparents = OtherParents->getBy(childId=>$article->{id})
  if $article->{id} && $article->{id} > 0;
my @stepparent_targets = $article->step_parents 
  if $article->{id} && $article->{id} > 0;
my %stepparent_targets = map { $_->{id}, $_ } @stepparent_targets;
my @stepparent_possibles = grep !$stepparent_targets{$_->{id}}, $articles->all;
my $stepparent_index;

my $child_index = -1;
%acts =
  (
   BSE::Util::Tags->basic(\%acts, $CGI::Q, $cfg),
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
                       -default=>$id?$article->{template}:
		       ($def_template || $levels{$level}{template}));
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
   ifType => sub {
     my ($which, $type) = split ' ', $_[0];
     $acts{$which} or return 0;
     $acts{$which}->('generator') eq "Generate::$type";
   },
   edit => \&edit_link,
   adminMenu => sub { $ROOT_URI . "admin/"; },
   iterate_kids_reset => sub { $allkids_index = -1 },
   iterate_kids => sub { ++$allkids_index < @allkids },
   ifKids => sub { @allkids },
   kid => 
   sub { 
     my $value = $allkids[$allkids_index]{$_[0]};
     defined $value or $value = '';
     CGI::escapeHTML($value)
   },
   ifStepKid => sub { exists $stepkids{$allkids[$allkids_index]{id}} },
   stepkid =>
   sub {
     my $value = $stepkids{$allkids[$allkids_index]{id}}{$_[0]};
     defined $value or $value = '';
     CGI::escapeHTML($value);
   },
   movestepkid =>
   sub {
     my $html = '';
     my $refreshto = CGI::escape($ENV{SCRIPT_NAME}
				 ."?id=$article->{id}#step");
     if ($allkids_index < $#allkids) {
       $html .= <<HTML
<a href="$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids[$allkids_index]{id}&other=$allkids[$allkids_index+1]{id}&refreshto=$refreshto"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
     }
     if ($allkids_index > 0) {
       $html .= <<HTML
<a href="$CGI_URI/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids[$allkids_index]{id}&other=$allkids[$allkids_index-1]{id}&refreshto=$refreshto"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
     }
     return $html;
   },
   date =>
   sub {
     my ($func, $args) = split ' ', $_[0], 2;
     $acts{$func} or return "** function $func not defined **";
     use BSE::Util::SQL qw/sql_to_date/;
     sql_to_date($acts{$func}->($args));
   },
   possible_stepkids =>
   sub {
#       @possibles =
#         sort { $a->{title} cmp $b->{title} }
#         grep $_->{generator} eq 'Generate::Product' && !$stepkids{$_->{id}},
#         $articles->all()
#  	 unless @possibles;
     @possibles = possible_stepkids($articles, \%stepkids)
       unless @possibles;
     my %labels = map { $_->{id}, "$_->{title} ($_->{id})" } @possibles;
     CGI::popup_menu(-name=>'stepkid',
		     -values => [ map $_->{id}, @possibles ],
		     -labels => \%labels);
   },
   ifPossibles =>
   sub {
     @possibles = possible_stepkids($articles, \%stepkids)
       unless @possibles;
#       @possibles =
#         sort { $a->{title} cmp $b->{title} }
#         grep $_->{generator} eq 'Generate::Product' && !$stepkids{$_->{id}},
#         $articles->all()
#  	 unless @possibles;
     @possibles;
   },
   ifStepParents => sub { @stepparents },
   iterate_stepparents_reset => sub { $stepparent_index = -1; },
   iterate_stepparents => sub { ++$stepparent_index < @stepparents },
   stepparent => sub { CGI::escapeHTML($stepparents[$stepparent_index]{$_[0]}) },
   stepparent_targ =>
   sub {
     CGI::escapeHTML($stepparent_targets[$stepparent_index]{$_[0]});
   },
   movestepparent =>
   sub {
     my $html = '';
     my $refreshto = CGI::escape($ENV{SCRIPT_NAME}
				 ."?id=$article->{id}#stepparents");
     if ($stepparent_index < $#stepparents) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepchild=$article->{id}&id=$stepparents[$stepparent_index]{parentId}&d=swap&other=$stepparents[$stepparent_index+1]{parentId}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
       }
       if ($stepparent_index > 0) {
	 $html .= <<HTML;
<a href="$CGI_URI/admin/move.pl?stepchild=$article->{id}&id=$stepparents[$stepparent_index]{parentId}&d=swap&other=$stepparents[$stepparent_index-1]{parentId}&refreshto=$refreshto&all=1"><img src="$IMAGES_URI/admin/move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
       }
       return $html;
     },
     ifStepparentPossibles => sub { @stepparent_possibles },
     stepparent_possibles => sub {
       popup_menu(-name=>'stepparent',
		  -values=>[ map $_->{id}, @stepparent_possibles ],
		  -labels=>{ map { $_->{id}, "$_->{title} ($_->{id})" } 
			     @stepparent_possibles });
     },
     BSE::Util::Tags->
     make_iterator(\@files, 'file', 'files', \$file_index),
  );

if ($imageEditor->action($CGI::Q)) {
  exit;
}

use BSE::FileEditor;
my $file_editor = 
  BSE::FileEditor->new(session=>\%session, cgi=>$CGI::Q, cfg=>$cfg,
		       backopts=>{ });
if ($file_editor->process_files()) {
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
  $message = shift if @_;
  # just substitute empty defaults into the blank page
  if (should_be_catalog($article, $parent, $articles)) {
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
    $data{threshold} = $levels{$level}{threshold}
      if !defined $data{threshold} || $data{threshold} =~ /^\s*$/;
    $data{summaryLength} = 200
      if !defined $data{summaryLength} || $data{summaryLength} =~ /^\s*$/;
  }
  $data{generator} = should_be_catalog($article, $parent, $articles) 
    ? 'Generate::Catalog' : 'Generate::Article';
  $data{lastModified} = epoch_to_sql(time);

  shift @columns;
  $article = $articles->add(@data{@columns});

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
    $link = $urlbase.$SHOP_URI."/shop$article->{id}.html";
    $article->setAdmin($CGI_URI."/admin/shopadmin.pl");
  }
  $article->setLink($link);
  $article->save();

  # save the images
  my @images = $imageEditor->images();
  my @imcols = Image->columns;
  splice(@imcols, 0, 2);
  for my $image (@images) {
    my $obj = Images->add($article->{id}, @$image{@imcols});
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
    print STDERR "Reparenting...\n";
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
  my @imcols = Image->columns;
  splice(@imcols, 0, 2);
  for my $image (@images) {
    Images->add($article->{id}, @$image{@imcols});
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

  print "Refresh: 0; url=\"$urlbase$article->{admin}\"\n";
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

    # remove any step(child|parent) links
    require 'OtherParents.pm';
    my @steprels = OtherParents->anylinks($deleteid);
    for my $link (@steprels) {
      $link->remove();
    }
    
    $delart->remove();
    $articles = Articles->new(1);
    use Util 'generate_article';
    generate_article($articles, $article) if $AUTO_GENERATE;
    @children = grep { $_->{id} != $deleteid } @children;
    start();
  }
}

sub add_stepkid {
  require 'BSE/Admin/StepParents.pm';
  eval {
    my $childId = param('stepkid');
    defined $childId
      or die "No stepkid supplied to add_stepkid";
    int($childId) eq $childId
      or die "Invalid stepkid supplied to add_stepkid";
    my $child = $articles->getByPkey($childId)
      or die "Article $childId not found";
    
    my $release = param('release');
    defined $release
      or $release = "01/01/2000";
    use BSE::Util::Valid qw/valid_date/;
    $release eq '' or valid_date($release)
      or die "Invalid release date";
    my $expire = param('expire');
    defined $expire
      or $expire = '31/12/2999';
    $expire eq '' or valid_date($expire)
      or die "Invalid expire data";
  
    my $newentry = 
      BSE::Admin::StepParents->add($article, $child, $release, $expire);
  };
  if ($@) {
    $message = $@;
    return start();
  }
  print "Refresh: 0; url=\"$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}#step\"\n";
  print "Content-type: text/html\n\n<HTML></HTML>\n";
}

sub del_stepkid {
  require 'BSE/Admin/StepParents.pm';

  eval {
    my $childId = param('stepkid');
    defined $childId
      or die "No stepkid supplied to add_stepkid";
    int($childId) eq $childId
      or die "Invalid stepkid supplied to add_stepkid";
    require 'Products.pm';
    my $child = $articles->getByPkey($childId)
      or die "Article $childId not found";
    
    BSE::Admin::StepParents->del($article, $child);
  };
  
  if ($@) {
    $message = $@;
    return start();
  }
  refresh('step');
}

sub save_stepkids {
  require 'BSE/Admin/StepParents.pm';
  my @stepcats = OtherParents->getBy(parentId=>$article->{id});
  my %stepcats = map { $_->{parentId}, $_ } @stepcats;
  my %datedefs = ( release => '2000-01-01', expire=>'2999-12-31' );
  for my $stepcat (@stepcats) {
    for my $name (qw/release expire/) {
      my $date = param($name.'_'.$stepcat->{childId});
      if (defined $date) {
	if ($date eq '') {
	  $date = $datedefs{$name};
	}
	elsif (valid_date($date)) {
	  use BSE::Util::SQL qw/date_to_sql/;
	  $date = date_to_sql($date);
	}
	else {
	  return refresh('', "Invalid date '$date'");
	}
	$stepcat->{$name} = $date;
      }
    }
    eval {
      $stepcat->save();
    };
    $@ and return refresh('', $@);
  }
  refresh('step');
}

#####################
# Step parents

sub add_stepparent {
  require 'BSE/Admin/StepParents.pm';
  #my $productid = param('id');

  $article->{id} && $article->{id} > 0
    or return start("No id supplied to add_stepproduct");
  
  eval {
    my $step_parent_id = param('stepparent');
    defined($step_parent_id)
      or die "No stepparent supplied to add_stepparent";
    int($step_parent_id) eq $step_parent_id
      or die "Invalid stepcat supplied to add_stepcat";
    my $step_parent = Articles->getByPkey($step_parent_id)
      or die "Parnet $step_parent_id not found\n";

    my $release = param('release');
    defined $release
      or $release = "01/01/2000";
    use BSE::Util::Valid qw/valid_date/;
    $release eq '' or valid_date($release)
      or die "Invalid release date";
    my $expire = param('expire');
    defined $expire
      or $expire = '31/12/2999';
    $expire eq '' or valid_date($expire)
      or die "Invalid expire data";
  
    my $newentry = 
      BSE::Admin::StepParents->add($step_parent, $article, $release, $expire);
  };
  $@ and return refresh('step', $@);

  return refresh('step');
}

sub del_stepparent {
  require 'BSE/Admin/StepParents.pm';

  $article->{id} && $article->{id} > 0
    or return refresh('', 'No article id supplied');
  my $step_parent_id = param('stepparent');
  defined($step_parent_id)
    or return refresh('stepparents', "No stepparent supplied to add_stepcat");
  int($step_parent_id) eq $step_parent_id
    or return refresh('stepparents', "Invalid stepparent supplied to add_stepparent");
  my $step_parent = $articles->getByPkey($step_parent_id)
    or return refresh('stepparent', "Catalog $step_parent_id not found");

  eval {
    BSE::Admin::StepParents->del($step_parent, $article);
  };
  $@ and return refresh('stepparents', $@);

  return refresh('stepparents');
}

sub save_stepparents {
  require 'BSE/Admin/StepParents.pm';

  $article->{id} && $article->{id} > 0
    or return refresh('', 'No article id supplied');
    
  my @stepparents = OtherParents->getBy(childId=>$article->{id});
  my %stepparents = map { $_->{parentId}, $_ } @stepparents;
  my %datedefs = ( release => '2000-01-01', expire=>'2999-12-31' );
  for my $stepparent (@stepparents) {
    for my $name (qw/release expire/) {
      my $date = param($name.'_'.$stepparent->{parentId});
      if (defined $date) {
	if ($date eq '') {
	  $date = $datedefs{$name};
	}
	elsif (valid_date($date)) {
	  use BSE::Util::SQL qw/date_to_sql/;
	  $date = date_to_sql($date);
	}
	else {
	  return refresh("Invalid date '$date'");
	}
	$stepparent->{$name} = $date;
      }
    }
    eval {
      $stepparent->save();
    };
    $@ and return refresh('', $@);
  }

  refresh('stepparents');
}

sub refresh {
  my ($name, $message) = @_;

  my $url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}";
  $url .= "&message=" . CGI::escape($message) if $message;
  $url .= "#$name" if $name;

  print "Refresh: 0; url=\"$url\"\n";
  print "Content-type: text/html\n\n<HTML></HTML>\n";
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
    my @values;
    my %labels;

    # articles that this article could become a child of
    if (should_be_catalog($article, $parent, $articles)) {
      # the parents of a catalog can be other catalogs or the shop
      my $shop = $articles->getByPkey($SHOPID);
      my @work = [ $SHOPID, $shop->{title} ];
      while (@work) {
	my ($id, $title) = @{pop @work};
	push(@values, $id);
	$labels{$id} = $title;
	push @work, map [ $_->{id}, $title.' / '.$_->{title} ],
	sort { $b->{displayOrder} <=> $a->{displayOrder} }
	  grep $_->{generator} eq 'Generate::Catalog', 
	  $articles->getBy(parentid=>$id);
      }
    }
    else {
      my @parents = $articles->getBy('level', $level-1);
      @parents = grep { $_->{generator} eq 'Generate::Article' 
			  && $_->{id} != $SHOPID } @parents;
      
      
      @values = ( map {$_->{id}} @parents );
      %labels = ( map { $_->{id} => "$_->{title} ($_->{id})" } @parents );
      
      if ($level == 1) {
	push @values, -1;
	$labels{-1} = "No parent - this is a section";
      }
      
      if ($id && reparent_updown()) {
	# we also list the siblings and grandparent (if any)
	my @siblings = grep $_->{id} != $id && $_->{id} != $SHOPID,
	$articles->getBy(parentid => $article->{parentid});
	push @values, map $_->{id}, @siblings;
	@labels{map $_->{id}, @siblings} =
	  map { "-- move down a level -- $_->{title} ($_->{id})" } @siblings;
	
	if ($article->{parentid} != -1) {
	  my $parent = $articles->getByPkey($article->{parentid});
	  if ($parent->{parentid} != -1) {
	    my $gparent = $articles->getByPkey($parent->{parentid});
	    push @values, $gparent->{id};
	    $labels{$gparent->{id}} =
	      "-- move up a level -- $gparent->{title} ($gparent->{id})";
	  }
	  else {
	    push @values, -1;
	    $labels{-1} = "-- move up a level -- become a section";
	  }
	}
      }
    }
    my $html;
    if (defined $article->{parentid}) {
      $html = popup_menu(-name=>'parentid',
			 -values=> \@values,
			 -labels => \%labels,
			 -default => $article->{parentid},
			 -override=>1);
    }
    else {
      $html = popup_menu(-name=>'parentid',
			 -values=> \@values,
			 -labels => \%labels,
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

sub should_be_catalog {
  my ($article, $parent, $articles) = @_;

  if ($article->{parentid} && (!$parent || $parent->{id} != $article->{parentid})) {
    $parent = $articles->getByPkey($article->{id});
  }

  return $article->{parentid} && $parent &&
    ($article->{parentid} == $SHOPID || 
     $parent->{generator} eq 'Generate::Catalog');
}

sub possible_stepkids {
  my ($articles, $stepkids) = @_;

  #@possibles =
  #  sort { $a->{title} cmp $b->{title} }
  #    grep $_->{generator} eq 'Generate::Product' && !$stepkids{$_->{id}},
  #    $articles->all();

  return sort { $a->{title} cmp $b->{title} }
    grep !$stepkids->{$_->{id}}, $articles->all;
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
