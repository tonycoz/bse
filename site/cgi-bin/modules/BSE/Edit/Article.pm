package BSE::Edit::Article;
use strict;
use HTML::Entities;
use base qw(BSE::Edit::Base);
use BSE::Util::Tags qw(tag_error_img);
use BSE::Util::SQL qw(now_sqldate);
use BSE::Util::Valid qw/valid_date/;
use BSE::Permissions;
use Util qw(custom_class);

sub article_dispatch {
  my ($self, $req, $article, $articles) = @_;

  BSE::Permissions->check_logon($req)
    or return BSE::Template->get_refresh($req->url('logon'), $req->cfg);

  my $cgi = $req->cgi;
  my $action;
  my %actions = $self->article_actions;
  for my $check (keys %actions) {
    if ($cgi->param($check) || $cgi->param("$check.x")) {
      $action = $check;
      last;
    }
  }
  my @extraargs;
  unless ($action) {
    ($action, @extraargs) = $self->other_article_actions($cgi);
  }
  $action ||= 'edit';
  my $method = $actions{$action};
  return $self->$method($req, $article, $articles, @extraargs);
}

sub noarticle_dispatch {
  my ($self, $req, $articles) = @_;

  BSE::Permissions->check_logon($req)
    or return BSE::Template->get_refresh($req->url('logon'), $req->cfg);

  my $cgi = $req->cgi;
  my $action = 'add';
  my %actions = $self->noarticle_actions;
  for my $check (keys %actions) {
    if ($cgi->param($check) || $cgi->param("$check.x")) {
      $action = $check;
      last;
    }
  }
  my $method = $actions{$action};
  return $self->$method($req, $articles);
}

sub edit_sections {
  my ($self, $req, $articles, $msg) = @_;

  BSE::Permissions->check_logon($req)
    or return BSE::Template->get_refresh($req->url('logon'), $req->cfg);

  my %article;
  my @cols = Article->columns;
  @article{@cols} = ('') x @cols;
  $article{id} = '-1';
  $article{parentid} = -1;
  $article{level} = 0;
  $article{body} = '';
  $article{listed} = 0;
  $article{generator} = $self->generator;
  $article{flags} = '';

  return $self->low_edit_form($req, \%article, $articles, $msg);
}

sub article_actions {
  my ($self) = @_;

  return
    (
     edit => 'edit_form',
     save => 'save',
     add_stepkid => 'add_stepkid',
     del_stepkid => 'del_stepkid',
     save_stepkids => 'save_stepkids',
     add_stepparent => 'add_stepparent',
     del_stepparent => 'del_stepparent',
     save_stepparents => 'save_stepparents',
     artimg => 'save_image_changes',
     addimg => 'add_image',
     remove => 'remove',
     showimages => 'show_images',
     process => 'save_image_changes',
     removeimg => 'remove_img',
     moveimgup => 'move_img_up',
     moveimgdown => 'move_img_down',
     filelist => 'filelist',
     fileadd => 'fileadd',
     fileswap => 'fileswap',
     filedel => 'filedel',
     filesave => 'filesave',
     hide => 'hide',
     unhide => 'unhide',
    );
}

sub other_article_actions {
  my ($self, $cgi) = @_;

  for my $param ($cgi->param) {
    if ($param =~ /^removeimg_(\d+)(\.x)?$/) {
      return ('removeimg', $1 );
    }
  }

  return;
}

sub noarticle_actions {
  return
    (
     add => 'add_form',
     save => 'save_new',
    );
}

sub get_parent {
  my ($self, $parentid, $articles) = @_;

  if ($parentid == -1) {
    return 
      {
       id => -1,
       title=>'All Sections',
       level => 0,
       listed => 0,
       parentid => undef,
      };
  }
  else {
    return $articles->getByPkey($parentid);
  }
}

sub tag_hash {
  my ($object, $args) = @_;

  my $value = $object->{$args};
  defined $value or $value = '';
  if ($value =~ /\cJ/ && $value =~ /\cM/) {
    $value =~ tr/\cM//d;
  }
  encode_entities($value);
}

sub tag_art_type {
  my ($level, $cfg) = @_;

  encode_entities($cfg->entry('level names', $level, 'Article'));
}

sub tag_if_new {
  my ($article) = @_;

  !$article->{id};
}

sub reparent_updown {
  return 1;
}

sub should_be_catalog {
  my ($self, $article, $parent, $articles) = @_;

  if ($article->{parentid} && (!$parent || $parent->{id} != $article->{parentid})) {
    $parent = $articles->getByPkey($article->{id});
  }

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');

  return $article->{parentid} && $parent &&
    ($article->{parentid} == $shopid || 
     $parent->{generator} eq 'Generate::Catalog');
}

sub possible_parents {
  my ($self, $article, $articles, $req) = @_;

  my %labels;
  my @values;

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  my @parents = $articles->getBy('level', $article->{level}-1);
  @parents = grep { $_->{generator} eq 'Generate::Article' 
		      && $_->{id} != $shopid } @parents;

  # user can only select parent they can add to
  @parents = grep $req->user_can('edit_add_child', $_), @parents;
  
  @values = ( map {$_->{id}} @parents );
  %labels = ( map { $_->{id} => "$_->{title} ($_->{id})" } @parents );
  
  if ($article->{level} == 1 && $req->user_can('edit_add_child')) {
    push @values, -1;
    $labels{-1} = "No parent - this is a section";
  }
  
  if ($article->{id} && $self->reparent_updown($article)) {
    # we also list the siblings and grandparent (if any)
    my @siblings = grep $_->{id} != $article->{id} && $_->{id} != $shopid,
    $articles->getBy(parentid => $article->{parentid});
    @siblings = grep $req->user_can('edit_add_child', $_), @siblings;
    push @values, map $_->{id}, @siblings;
    @labels{map $_->{id}, @siblings} =
      map { "-- move down a level -- $_->{title} ($_->{id})" } @siblings;
    
    if ($article->{parentid} != -1) {
      my $parent = $articles->getByPkey($article->{parentid});
      if ($parent->{parentid} != -1) {
	my $gparent = $articles->getByPkey($parent->{parentid});
	if ($req->user_can('edit_add_child', $gparent)) {
	  push @values, $gparent->{id};
	  $labels{$gparent->{id}} =
	    "-- move up a level -- $gparent->{title} ($gparent->{id})";
	}
      }
      else {
	if ($req->user_can('edit_add_child')) {
	  push @values, -1;
	  $labels{-1} = "-- move up a level -- become a section";
	}
      }
    }
  }

  return (\@values, \%labels);
}

sub tag_list {
  my ($self, $article, $articles, $cgi, $req, $what) = @_;

  if ($what eq 'listed') {
    my @values = qw(0 1);
    my %labels = ( 0=>"No", 1=>"Yes");
    if ($article->{level} <= 2) {
      $labels{2} = "In Sections, but not menu";
      push(@values, 2);
    }
    else {
      $labels{2} = "In content, but not menus";
      push(@values, 2);
    }
    return $cgi->popup_menu(-name=>'listed',
			    -values=>\@values,
			    -labels=>\%labels,
			    -default=>$article->{listed});
  }
  else {
    my ($values, $labels) = $self->possible_parents($article, $articles, $req);
    my $html;
    if (defined $article->{parentid}) {
      $html = $cgi->popup_menu(-name=>'parentid',
			       -values=> $values,
			       -labels => $labels,
			       -default => $article->{parentid},
			       -override=>1);
    }
    else {
      $html = $cgi->popup_menu(-name=>'parentid',
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

sub tag_checked {
  my ($arg, $acts, $funcname, $templater) = @_;
  my ($func, $args) = split ' ', $arg, 2;
  return $templater->perform($acts, $func, $args) ? 'checked' : '';
}

sub iter_get_images {
  my ($article) = @_;

  $article->{id} or return;
  $article->images;
}

sub iter_get_kids {
  my ($article, $articles) = @_;

  my @children;
  $article->{id} or return;
  if (UNIVERSAL::isa($article, 'Article')) {
    @children = $article->children;
  }
  elsif ($article->{id}) {
    @children = $articles->children($article->{id});
  }

  return sort { $b->{displayOrder} <=> $a->{displayOrder} } @children;
}

sub tag_if_have_child_type {
  my ($level, $cfg) = @_;

  defined $cfg->entry("level names", $level+1);
}

sub tag_is {
  my ($args, $acts, $isname, $templater) = @_;

  my ($func, $funcargs) = split ' ', $args, 2;
  return $templater->perform($acts, $func, $funcargs) ? 'Yes' : 'No';
}

sub default_template {
  my ($self, $article, $cfg, $templates) = @_;

  if ($article->{parentid}) {
    my $template = $cfg->entry("children of $article->{parentid}", "template");
    return $template 
      if $template && grep $_ eq $template, @$templates;
  }
  if ($article->{level}) {
    my $template = $cfg->entry("level $article->{level}", "template");
    return $template 
      if $template && grep $_ eq $template, @$templates;
  }
  return $templates->[0];
}

sub tag_templates {
  my ($self, $article, $cfg, $cgi) = @_;

  my @templates = sort $self->templates($article);
  my $default;
  if ($article->{template} && grep $_ eq $article->{template}, @templates) {
    $default = $article->{template};
  }
  else {
    my @options;
    $default = $self->default_template($article, $cfg, \@templates);
  }
  return $cgi->popup_menu(-name=>'template',
			  -values=>\@templates,
			  -default=>$default,
			  -override=>1);
}

sub title_images {
  my ($self, $article) = @_;

  my @title_images;
  my $imagedir = $self->{cfg}->entry('paths', 'images', $Constants::IMAGEDIR);
  if (opendir TITLE_IMAGES, "$imagedir/titles") {
    @title_images = sort 
      grep -f "$imagedir/titles/$_" && /\.(gif|jpeg|jpg|png)$/i,
      readdir TITLE_IMAGES;
    closedir TITLE_IMAGES;
  }

  @title_images;
}

sub tag_title_images  {
  my ($self, $article, $cfg, $cgi) = @_;

  my @images = $self->title_images($article);
  my @values = ( '', @images );
  my %labels = ( '' => 'None', map { $_ => $_ } @images );
  return $cgi->
    popup_menu(-name=>'titleImage',
	       -values=>\@values,
	       -labels=>\%labels,
	       -default=>$article->{id} ? $article->{titleImage} : '',
	       -override=>1);
}

sub base_template_dirs {
  return ( "common" );
}

sub template_dirs {
  my ($self, $article) = @_;

  my @dirs = $self->base_template_dirs;
  if (my $parentid = $article->{parentid}) {
    my $section = "children of $parentid";
    if (my $dirs = $self->{cfg}->entry($section, 'template_dirs')) {
      push @dirs, split /,/, $dirs;
    }
  }
  if (my $id = $article->{id}) {
    my $section = "article $id";
    if (my $dirs = $self->{cfg}->entry($section, 'template_dirs')) {
      push @dirs, split /,/, $dirs;
    }
  }
  if ($article->{level}) {
    push @dirs, $article->{level};
    my $dirs = $self->{cfg}->entry("level $article->{level}", 'template_dirs');
    push @dirs, split /,/, $dirs if $dirs;
  }

  @dirs;
}

sub templates {
  my ($self, $article) = @_;

  my @dirs = $self->template_dirs($article);
  my @templates;
  my @basedirs = BSE::Template->template_dirs($self->{cfg});
  for my $basedir (@basedirs) {
    for my $dir (@dirs) {
      my $path = File::Spec->catdir($basedir, $dir);
      if (-d $path) {
	if (opendir TEMPLATE_DIR, $path) {
	  push(@templates, sort map "$dir/$_",
	       grep -f "$path/$_" && /\.(tmpl|html)$/i, readdir TEMPLATE_DIR);
	  closedir TEMPLATE_DIR;
	}
      }
    }
  }

  # eliminate any dups, and order it nicely
  my %seen;
  @templates = sort { lc($a) cmp lc($b) }
    grep !$seen{$_}++, @templates;
  
  return (@templates, $self->extra_templates($article));
}

sub extra_templates {
  my ($self, $article) = @_;

  my $basedir = $self->{cfg}->entryVar('paths', 'templates');
  my @templates;
  if (my $id = $article->{id}) {
    push @templates, 'index.tmpl'
      if $id == 1 && -f "$basedir/index.html";
    push @templates, 'index2.tmpl'
      if $id == 2 && -f "$basedir/index2.html";
    my $shopid = $self->{cfg}->entryErr('articles', 'shop');
    push @templates, "shop_sect.tmpl"
      if $id == $shopid && -f "$basedir/shop_sect.tmpl";
    my $section = "article $id";
    my $extras = $self->{cfg}->entry($section, 'extra_templates');
    push @templates, grep /\.(tmpl|html)$/i, split /,/, $extras
      if $extras;
  }

  @templates;
}

sub edit_parent {
  my ($article) = @_;

  return '' unless $article->{id} && $article->{id} != -1;
  return <<HTML;
<a href="$ENV{SCRIPT_NAME}?id=$article->{parentid}">Edit parent</a> |
HTML
}

sub iter_allkids {
  my ($article) = @_;

  return unless $article->{id} && $article->{id} > 0;
  $article->allkids;
}

sub _load_step_kids {
  my ($article, $step_kids) = @_;

  my @stepkids = OtherParents->getBy(parentId=>$article->{id}) if $article->{id};
  %$step_kids = map { $_->{childId} => $_ } @stepkids;
  use Data::Dumper;
  print STDERR "stepkids:\n", Dumper($step_kids);
  $step_kids->{loaded} = 1;
}

sub tag_if_step_kid {
  my ($article, $allkids, $rallkid_index, $step_kids) = @_;

  _load_step_kids($article, $step_kids) unless $step_kids->{loaded};

  my $kid = $allkids->[$$rallkid_index]
    or return;
  exists $step_kids->{$kid->{id}};
}

sub tag_step_kid {
  my ($article, $allkids, $rallkid_index, $step_kids, $arg) = @_;

  _load_step_kids($article, $step_kids) unless $step_kids->{loaded};

  my $kid = $allkids->[$$rallkid_index]
    or return '';
  print STDERR "found kid (want $arg): ", Dumper $kid;
  encode_entities($step_kids->{$kid->{id}}{$arg});
}

sub tag_move_stepkid {
  my ($self, $cgi, $req, $article, $allkids, $rallkids_index, $arg,
      $acts, $funcname, $templater) = @_;

  $req->user_can(edit_reorder_children => $article)
    or return '';

  @$allkids > 1 or return '';

  my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
  $img_prefix = '' unless defined $img_prefix;
  $urladd = '' unless defined $urladd;

  my $cgi_uri = $self->{cfg}->entry('uri', 'cgi', '/cgi-bin');
  my $images_uri = $self->{cfg}->entry('uri', 'images', '/images');
  my $html = '';
  my $url = $ENV{SCRIPT_NAME} . "?id=$article->{id}";
  if ($cgi->param('_t')) {
    $url .= "&_t=".$cgi->param('_t');
  }
  $url .= $urladd;
  $url .= "#step";
  my $refreshto = CGI::escape($url);
  my $blank = qq!<img src="$images_uri/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;
  if ($$rallkids_index < $#$allkids) {
    $html .= <<HTML;
<a href="$cgi_uri/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids->[$$rallkids_index]{id}&other=$allkids->[$$rallkids_index+1]{id}&refreshto=$refreshto"><img src="$images_uri/admin/${img_prefix}move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
  }
  else {
    $html .= $blank;
  }
  if ($$rallkids_index > 0) {
    $html .= <<HTML;
<a href="$cgi_uri/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids->[$$rallkids_index]{id}&other=$allkids->[$$rallkids_index-1]{id}&refreshto=$refreshto"><img src="$images_uri/admin/${img_prefix}move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
  }
  else {
    $html .= $blank;
  }
  $html =~ tr/\n//d;
  return $html;
}

sub possible_stepkids {
  my ($req, $article, $articles, $stepkids) = @_;

  $req->user_can(edit_stepkid_add => $article)
    or return;

  my @possible = sort { lc $a->{title} cmp lc $b->{title} }
    grep !$stepkids->{$_->{id}}, $articles->all;
  if ($req->access_control) {
    @possible = grep $req->user_can(edit_stepparent_add => $_), @possible;
  }
  return @possible;
}

sub tag_possible_stepkids {
  my ($step_kids, $req, $article, $possstepkids, $articles, $cgi) = @_;

  _load_step_kids($article, $step_kids) unless $step_kids->{loaded};
  @$possstepkids = possible_stepkids($req, $article, $articles, $step_kids)
    unless @$possstepkids;
  my %labels = map { $_->{id} => "$_->{title} ($_->{id})" } @$possstepkids;
  return
    $cgi->popup_menu(-name=>'stepkid',
		     -values=> [ map $_->{id}, @$possstepkids ],
		     -labels => \%labels);
}

sub tag_if_possible_stepkids {
  my ($step_kids, $req, $article, $possstepkids, $articles, $cgi) = @_;

  _load_step_kids($article, $step_kids) unless $step_kids->{loaded};
  @$possstepkids = possible_stepkids($req, $article, $articles, $step_kids)
    unless @$possstepkids;
  
  @$possstepkids;
}

sub iter_get_stepparents {
  my ($article) = @_;

  return unless $article->{id} && $article->{id} > 0;

  OtherParents->getBy(childId=>$article->{id});
}

sub tag_ifStepParents {
  my ($args, $acts, $funcname, $templater) = @_;

  return $templater->perform($acts, 'ifStepparents', '');
}

sub tag_stepparent_targ {
  my ($article, $targs, $rindex, $arg) = @_;

  if ($article->{id} && $article->{id} > 0 && !@$targs) {
    @$targs = $article->step_parents;
  }
  encode_entities($targs->[$$rindex]{$arg});
}

sub tag_move_stepparent {
  my ($self, $cgi, $req, $article, $stepparents, $rindex, $arg,
      $acts, $funcname, $templater) = @_;

  $req->user_can(edit_reorder_stepparents => $article)
    or return '';

  @$stepparents > 1 or return '';

  my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
  $img_prefix = '' unless defined $img_prefix;
  $urladd = '' unless defined $urladd;

  my $cgi_uri = $self->{cfg}->entry('uri', 'cgi', '/cgi-bin');
  my $images_uri = $self->{cfg}->entry('uri', 'images', '/images');
  my $html = '';
  my $url = $ENV{SCRIPT_NAME} . "?id=$article->{id}";
  if ($cgi->param('_t')) {
    $url .= "&_t=".$cgi->param('_t');
  }
  $url .= $urladd;
  $url .= "#stepparents";
  my $blank = qq!<img src="$images_uri/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" />!;
  my $refreshto = CGI::escape($url);
  if ($$rindex < $#$stepparents) {
    $html .= <<HTML;
<a href="$cgi_uri/admin/move.pl?stepchild=$article->{id}&id=$stepparents->[$$rindex]{parentId}&d=swap&other=$stepparents->[$$rindex+1]{parentId}&refreshto=$refreshto&all=1"><img src="$images_uri/admin/${img_prefix}move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
  }
  else {
    $html .= $blank;
  }
  if ($$rindex > 0) {
    $html .= <<HTML;
<a href="$cgi_uri/admin/move.pl?stepchild=$article->{id}&id=$stepparents->[$$rindex]{parentId}&d=swap&other=$stepparents->[$$rindex-1]{parentId}&refreshto=$refreshto&all=1"><img src="$images_uri/admin/${img_prefix}move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
  }
  else {
    $html .= $blank;
  }
  $html =~ tr/\n//d;
  return $html;
}

sub _stepparent_possibles {
  my ($req, $article, $articles, $targs) = @_;

  $req->user_can(edit_stepparent_add => $article)
    or return;

  @$targs = $article->step_parents unless @$targs;
  my %targs = map { $_->{id}, 1 } @$targs;
  my @possibles = grep !$targs{$_->{id}}, $articles->all;
  if ($req->access_control) {
    @possibles = grep $req->user_can(edit_stepkid_add => $_), @possibles;
  }
  @possibles = sort { lc $a->{title} cmp lc $b->{title} } @possibles;

  return @possibles;
}

sub tag_if_stepparent_possibles {
  my ($req, $article, $articles, $targs, $possibles) = @_;

  if ($article->{id} && $article->{id} > 0 && !@$possibles) {
    @$possibles = _stepparent_possibles($req, $article, $articles, $targs);
  }
  scalar @$possibles;
}

sub tag_stepparent_possibles {
  my ($cgi, $req, $article, $articles, $targs, $possibles) = @_;

  if ($article->{id} && $article->{id} > 0 && !@$possibles) {
    @$possibles = _stepparent_possibles($req, $article, $articles, $targs);
  }
  $cgi->popup_menu(-name=>'stepparent',
		   -values => [ map $_->{id}, @$possibles ],
		   -labels => { map { $_->{id}, "$_->{title} ($_->{id})" }
				@$possibles });
}

sub iter_files {
  my ($article) = @_;

  return unless $article->{id} && $article->{id} > 0;

  return $article->files;
}

sub tag_edit_parent {
  my ($article) = @_;

  return '' unless $article->{id} && $article->{id} != -1;

  return <<HTML;
<a href="$ENV{SCRIPT_NAME}?id=$article->{parentid}">Edit parent</a> |
HTML
}

sub tag_if_children {
  my ($args, $acts, $funcname, $templater) = @_;

  return $templater->perform($acts, 'ifChildren', '');
}

sub tag_movechild {
  my ($self, $req, $article, $kids, $rindex, $arg,
      $acts, $funcname, $templater) = @_;

  $req->user_can('edit_reorder_children', $article)
    or return '';

  @$kids > 1 or return '';

  $$rindex >=0 && $$rindex < @$kids
    or return '** movechild can only be used in the children iterator **';

  my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
  $img_prefix = '' unless defined $img_prefix;
  $urladd = '' unless defined $urladd;

  my $cgi_uri = $self->{cfg}->entry('uri', 'cgi', '/cgi-bin');
  my $images_uri = $self->{cfg}->entry('uri', 'images', '/images');
  my $html = '';
  my $nomove = '<img src="/images/trans_pixel.gif" width="17" height="13" border="0" alt="" align="absbottom">';
  my $id = $kids->[$$rindex]{id};
  if ($$rindex < $#$kids) {
    $html .= <<HTML;
<a href="$cgi_uri/admin/move.pl?id=$id&d=down&edit=1&all=1"><img src="$images_uri/admin/${img_prefix}move_down.gif" width="17" height="13" alt="Move Down" border="0" align="absbottom"></a>
HTML
  }
  else {
    $html .= $nomove;
  }
  if ($$rindex > 0) {
    $html .= <<HTML;
<a href="$cgi_uri/admin/move.pl?id=$id&d=up&edit=1&all=1"><img src="$images_uri/admin/${img_prefix}move_up.gif" width="17" height="13" alt="Move Up" border="0" align="absbottom"></a>
HTML
  }
  else {
    $html .= $nomove;
  }
  $html =~ tr/\n//d;

  $html;
}

sub tag_edit_link {
  my ($args, $acts, $funcname, $templater) = @_;
  my ($which, $name) = split / /, $args, 2;
  $name ||= 'Edit';
  my $gen_class;
  if ($acts->{$which} 
      && ($gen_class = $templater->perform($acts, $which, 'generator'))) {
    eval "use $gen_class";
    unless ($@) {
      my $gen = $gen_class->new;
      my $link = $gen->edit_link($templater->perform($acts, $which, 'id'));
      return qq!<a href="$link">$name</a>!;
    }
  }
  return '';
}

sub tag_imgmove {
  my ($req, $article, $rindex, $images, $arg,
      $acts, $funcname, $templater) = @_;

  $req->user_can(edit_images_reorder => $article)
    or return '';

  @$images > 1 or return '';

  $$rindex >= 0 && $$rindex < @$images 
    or return '** imgmove can only be used in image iterator **';

  my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
  $img_prefix = '' unless defined $img_prefix;
  $urladd = '' unless defined $urladd;

  my $urlbase = $req->cfg->entryVar('site', 'url');
  my $url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}&showimages=1$urladd";
  $url = CGI::escape($url);

  my $html = '';
  my $nomove = '<img src="/images/trans_pixel.gif" width="17" height="13" border="0" alt="" align="absbottom">';
  my $image = $images->[$$rindex];
  if ($$rindex > 0) {
    $html .= <<HTML
<a href="$ENV{SCRIPT_NAME}?id=$article->{id}&moveimgup=1&imageid=$image->{id}&r=$url"><img src="/images/admin/${img_prefix}move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
  }
  else {
    $html .= $nomove;
  }
  if ($$rindex < $#$images) {
    $html .= <<HTML
<a href="$ENV{SCRIPT_NAME}?id=$article->{id}&moveimgdown=1&imageid=$image->{id}&r=$url"><img src="/images/admin/${img_prefix}move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
  }
  else {
    $html .= $nomove;
  }
  $html =~ tr/\n//d;
  return $html;
}

sub tag_movefiles {
  my ($self, $req, $article, $files, $rindex, $arg,
      $acts, $funcname, $templater) = @_;

  $req->user_can('edit_files_reorder', $article)
    or return '';

  @$files > 1 or return '';

  my ($img_prefix, $urladd) = DevHelp::Tags->get_parms($arg, $acts, $templater);
  $img_prefix = '' unless defined $img_prefix;
  $urladd = '' unless defined $urladd;

  my $html = '';

  $$rindex >= 0 && $$rindex < @$files
    or return '** movefiles can only be used in the files iterator **';

  my $nomove = '<img src="/images/trans_pixel.gif" width="17" height="13" border="0" alt="" align="absbottom">';
  my $images_uri = $self->{cfg}->entry('uri', 'images', '/images');

  my $urlbase = $self->{cfg}->entryVar('site', 'url');
  my $url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}&filelist=1$urladd";
  $url = CGI::escape($url);
  
  if ($$rindex < $#$files) {
    $html .= <<HTML;
<a href="$ENV{SCRIPT_NAME}?fileswap=1&id=$article->{id}&file1=$files->[$$rindex]{id}&file2=$files->[$$rindex+1]{id}&r=$url"><img src="$images_uri/admin/${img_prefix}move_down.gif" width="17" height="13" border="0" alt="Move Down" align="absbottom"></a>
HTML
  }
  else {
    $html .= $nomove;
  }
  if ($$rindex > 0) {
    $html .= <<HTML;
<a href="$ENV{SCRIPT_NAME}?fileswap=1&id=$article->{id}&file1=$files->[$$rindex]{id}&file2=$files->[$$rindex-1]{id}&r=$url"><img src="$images_uri/admin/${img_prefix}move_up.gif" width="17" height="13" border="0" alt="Move Up" align="absbottom"></a>
HTML
  }
  else {
    $html .= $nomove;
  }
  $html =~ tr/\n//d;
  $html;
}

sub tag_old {
  my ($article, $cgi, $args, $acts, $funcname, $templater) = @_;

  my ($col, $func, $funcargs) = split ' ', $args, 3;
  my $value = $cgi->param($col);
  if (defined $value) {
    return encode_entities($value);
  }
  else {
    if ($func) {
      return $templater->perform($acts, $func, $funcargs);
    }
    else {
      $value = $article->{$args};
      defined $value or $value = '';
      return encode_entities($value);
    }
  }
}

# sub tag_error_img {
#   my ($self, $errors, $args) = @_;

#   return '' unless $errors->{$args};
#   my $images_uri = $self->{cfg}->entry('uri', 'images', '/images');
#   my $encoded = encode_entities($errors->{$args});
#   return qq!<img src="$images_uri/admin/error.gif" alt="$encoded" title="$encoded" border="0" align="top">!; 
# }

sub iter_admin_users {
  require BSE::TB::AdminUsers;

  BSE::TB::AdminUsers->all;
}

sub iter_admin_groups {
  require BSE::TB::AdminGroups;

  BSE::TB::AdminGroups->all;
}

sub tag_if_field_perm {
  my ($req, $article, $field) = @_;

  unless ($field =~ /^\w+$/) {
    print STDERR "Bad fieldname '$field'\n";
    return;
  }
  if ($article->{id}) {
    return $req->user_can("edit_field_edit_$field", $article);
  }
  else {
    #print STDERR "adding, always successful\n";
    return 1;
  }
}

sub tag_default {
  my ($self, $req, $article, $args, $acts, $funcname, $templater) = @_;

  my ($col, $func, $funcargs) = split ' ', $args, 3;
  if ($article->{id}) {
    if ($func) {
      return $templater->perform($acts, $func, $funcargs);
    }
    else {
      my $value = $article->{$args};
      defined $value or $value = '';
      return encode_entities($value);
    }
  }
  else {
    my $value = $self->default_value($req, $article, $col);
    return encode_entities($value);
  }
}

sub iter_flags {
  my ($self) = @_;

  $self->flags;
}

sub tag_if_flag_set {
  my ($article, $arg, $acts, $funcname, $templater) = @_;

  my @args = DevHelp::Tags->get_parms($arg, $acts, $templater);
  @args or return;

  return index($article->{flags}, $args[0]) >= 0;
}

sub iter_crumbs {
  my ($article, $articles) = @_;

  my @crumbs;
  my $temp = $article;
  defined($temp->{parentid}) or return;
  while ($temp->{parentid} > 0
	 and my $crumb = $articles->getByPkey($temp->{parentid})) {
    unshift @crumbs, $crumb;
    $temp = $crumb;
  }

  @crumbs;
}

sub tag_typename {
  my ($args, $acts, $funcname, $templater) = @_;

  exists $acts->{$args} or return "** need an article name **";
  my $generator = $templater->perform($acts, $args, 'generator');

  $generator =~ /^(?:BSE::)?Generate::(\w+)$/
    or return "** invalid generator $generator **";

  return $1;
}

sub low_edit_tags {
  my ($self, $acts, $request, $article, $articles, $msg, $errors) = @_;

  my $cgi = $request->cgi;
  $msg ||= $cgi->param('message');
  $msg ||= '';
  $errors ||= {};
  if (keys %$errors && !$msg) {
    # try to get the errors in the same order as the table
    my @cols = $self->table_object($articles)->rowClass->columns;
    my %work = %$errors;
    my @out = grep defined, delete @work{@cols};

    $msg = join "<br>", @out, values %work;
  }
  my $parent;
  if ($article->{id}) {
    if ($article->{parentid} > 0) {
      $parent = $article->parent;
    }
    else {
      $parent = { title=>"No parent - this is a section", id=>-1 };
    }
  }
  else {
    $parent = { title=>"How did we get here?", id=>0 };
  }
  my @images;
  my $image_index;
  my @children;
  my $child_index;
  my %stepkids;
  my $cfg = $self->{cfg};
  my @allkids;
  my $allkid_index;
  my @possstepkids;
  my @stepparents;
  my $stepparent_index;
  my @stepparent_targs;
  my @stepparentpossibles;
  my @files;
  my $file_index;
  return
    (
     BSE::Util::Tags->basic($acts, $cgi, $cfg),
     BSE::Util::Tags->admin($acts, $cfg),
     BSE::Util::Tags->secure($request),
     article => [ \&tag_hash, $article ],
     old => [ \&tag_old, $article, $cgi ],
     default => [ \&tag_default, $self, $request, $article ],
     articleType => [ \&tag_art_type, $article->{level}, $cfg ],
     parentType => [ \&tag_art_type, $article->{level}-1, $cfg ],
     ifNew => [ \&tag_if_new, $article ],
     list => [ \&tag_list, $self, $article, $articles, $cgi, $request ],
     script => $ENV{SCRIPT_NAME},
     level => $article->{level},
     checked => \&tag_checked,
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_images, $article ], 'image', 'images', \@images, 
      \$image_index),
     imgmove => [ \&tag_imgmove, $request, $article, \$image_index, \@images ],
     message => $msg,
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_kids, $article, $articles ], 
      'child', 'children', \@children, \$child_index),
     ifchildren => \&tag_if_children,
     childtype => [ \&tag_art_type, $article->{level}+1, $cfg ],
     ifHaveChildType => [ \&tag_if_have_child_type, $article->{level}, $cfg ],
     movechild => [ \&tag_movechild, $self, $request, $article, \@children, 
		    \$child_index],
     is => \&tag_is,
     templates => [ \&tag_templates, $self, $article, $cfg, $cgi ],
     titleImages => [ \&tag_title_images, $self, $article, $cfg, $cgi ],
     editParent => [ \&tag_edit_parent, $article ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_allkids, $article ], 'kid', 'kids', \@allkids, \$allkid_index),
     ifStepKid => 
     [ \&tag_if_step_kid, $article, \@allkids, \$allkid_index, \%stepkids ],
     stepkid => [ \&tag_step_kid, $article, \@allkids, \$allkid_index, 
		  \%stepkids ],
     movestepkid => 
     [ \&tag_move_stepkid, $self, $cgi, $request, $article, \@allkids, 
       \$allkid_index ],
     possible_stepkids =>
     [ \&tag_possible_stepkids, \%stepkids, $request, $article, 
       \@possstepkids, $articles, $cgi ],
     ifPossibles => 
     [ \&tag_if_possible_stepkids, \%stepkids, $request, $article, 
       \@possstepkids, $articles, $cgi ],
     DevHelp::Tags->make_iterator2
     ( [ \&iter_get_stepparents, $article ], 'stepparent', 'stepparents', 
       \@stepparents, \$stepparent_index),
     ifStepParents => \&tag_ifStepParents,
     stepparent_targ => 
     [ \&tag_stepparent_targ, $article, \@stepparent_targs, 
       \$stepparent_index ],
     movestepparent => 
     [ \&tag_move_stepparent, $self, $cgi, $request, $article, \@stepparents, 
       \$stepparent_index ],
     ifStepparentPossibles =>
     [ \&tag_if_stepparent_possibles, $request, $article, $articles, 
       \@stepparent_targs, \@stepparentpossibles, ],
     stepparent_possibles =>
     [ \&tag_stepparent_possibles, $cgi, $request, $article, $articles, 
       \@stepparent_targs, \@stepparentpossibles, ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_files, $article ], 'file', 'files', \@files, \$file_index ),
     movefiles => 
     [ \&tag_movefiles, $self, $request, $article, \@files, \$file_index ],
     DevHelp::Tags->make_iterator2
     (\&iter_admin_users, 'iadminuser', 'adminusers'),
     DevHelp::Tags->make_iterator2
     (\&iter_admin_groups, 'iadmingroup', 'admingroups'),
     edit => \&tag_edit_link,
     error => [ \&tag_hash, $errors ],
     error_img => [ \&tag_error_img, $cfg, $errors ],
     ifFieldPerm => [ \&tag_if_field_perm, $request, $article ],
     parent => [ \&tag_hash, $parent ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_flags, $self ], 'flag', 'flags' ),
     ifFlagSet => [ \&tag_if_flag_set, $article ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_crumbs, $article, $articles ], 'crumb', 'crumbs' ),
     typename => \&tag_typename,
    );
}

sub edit_template {
  my ($self, $article, $cgi) = @_;

  my $base = $article->{level};
  my $t = $cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $base = $t;
  }
  return $self->{cfg}->entry('admin templates', $base, 
			     "admin/edit_$base");
}

sub add_template {
  my ($self, $article, $cgi) = @_;

  $self->edit_template($article, $cgi);
}

sub low_edit_form {
  my ($self, $request, $article, $articles, $msg, $errors) = @_;

  my $cgi = $request->cgi;
  my %acts;
  %acts = $self->low_edit_tags(\%acts, $request, $article, $articles, $msg,
			      $errors);
  my $template = $article->{id} ? 
    $self->edit_template($article, $cgi) : $self->add_template($article, $cgi);

  return BSE::Template->get_response($template, $request->cfg, \%acts);
}

sub edit_form {
  my ($self, $request, $article, $articles, $msg, $errors) = @_;

  return $self->low_edit_form($request, $article, $articles, $msg, $errors);
}

sub add_form {
  my ($self, $req, $articles, $msg, $errors) = @_;

  my $level;
  my $cgi = $req->cgi;
  my $parentid = $cgi->param('parentid');
  if ($parentid) {
    if ($parentid =~ /^\d+$/) {
      if (my $parent = $self->get_parent($parentid, $articles)) {
	$level = $parent->{level}+1;
      }
      else {
	$parentid = undef;
      }
    }
    elsif ($parentid eq "-1") {
      $level = 1;
    }
  }
  unless (defined $level) {
    $level = $cgi->param('level');
    undef $level unless defined $level && $level =~ /^\d+$/
      && $level > 0 && $level < 100;
    defined $level or $level = 3;
  }
  
  my %article;
  my @cols = Article->columns;
  @article{@cols} = ('') x @cols;
  $article{id} = '';
  $article{parentid} = $parentid;
  $article{level} = $level;
  $article{body} = '<maximum of 64Kb>';
  $article{listed} = 1;
  $article{generator} = $self->generator;

  my ($values, $labels) = $self->possible_parents(\%article, $articles, $req);
  @$values
    or return $self->edit_sections($req, $articles, 
		"You can't add children to any article at that level");

  return $self->low_edit_form($req, \%article, $articles, $msg, $errors);
}

sub generator { 'Generate::Article' }

sub typename {
  my ($self) = @_;

  my $gen = $self->generator;

  ($gen =~ /(\w+)$/)[0] || 'Article';
}

sub _validate_common {
  my ($self, $data, $articles, $errors, $article) = @_;

#   if (defined $data->{parentid} && $data->{parentid} =~ /^(?:-1|\d+)$/) {
#     unless ($data->{parentid} == -1 or 
# 	    $articles->getByPkey($data->{parentid})) {
#       $errors->{parentid} = "Selected parent article doesn't exist";
#     }
#   }
#   else {
#     $errors->{parentid} = "You need to select a valid parent";
#   }
  if (exists $data->{title} && $data->{title} !~ /\S/) {
    $errors->{title} = "Please enter a title";
  }

  if (exists $data->{template} && $data->{template} =~ /\.\./) {
    $errors->{template} = "Please only select templates from the list provided";
  }
  
}

sub validate {
  my ($self, $data, $articles, $errors) = @_;

  $self->_validate_common($data, $articles, $errors);
  custom_class($self->{cfg})
    ->article_validate($data, undef, $self->typename, $errors);

  return !keys %$errors;
}

sub validate_old {
  my ($self, $article, $data, $articles, $errors) = @_;

  $self->_validate_common($data, $articles, $errors, $article);
  custom_class($self->{cfg})
    ->article_validate($data, $article, $self->typename, $errors);

  if (exists $data->{release} && !valid_date($data->{release})) {
    $errors->{release} = "Invalid release date";
  }

  return !keys %$errors;
}

sub validate_parent {
  1;
}

sub fill_new_data {
  my ($self, $req, $data, $articles) = @_;

  custom_class($self->{cfg})
    ->article_fill_new($data, $self->typename);

  1;
}

sub make_link {
  my ($self, $article) = @_;

  my $article_uri = $self->{cfg}->entry('uri', 'articles', '/a');
  my $link = "$article_uri/$article->{id}.html";
  my $link_titles = $self->{cfg}->entryBool('basic', 'link_titles', 0);
  if ($link_titles) {
    (my $extra = lc $article->{title}) =~ tr/a-z0-9/_/sc;
    $link .= "/".$extra;
  }

  $link;
}

sub save_new {
  my ($self, $req, $articles) = @_;
  
  my $cgi = $req->cgi;
  my %data;
  my $table_object = $self->table_object($articles);
  my @columns = $table_object->rowClass->columns;
  $self->save_thumbnail($cgi, undef, \%data);
  for my $name (@columns) {
    $data{$name} = $cgi->param($name) 
      if defined $cgi->param($name);
  }
  $data{flags} = join '', sort $cgi->param('flags');

  my $msg;
  my %errors;
  $self->validate(\%data, $articles, \%errors)
    or return $self->add_form($req, $articles, $msg, \%errors);

  my $parent;
  if ($data{parentid} > 0) {
    $parent = $articles->getByPkey($data{parentid}) or die;
    $req->user_can('edit_add_child', $parent)
      or return $self->add_form($req, $articles,
				"You cannot add a child to that article");
    for my $name (@columns) {
      if (exists $data{$name} && 
	  !$req->user_can("edit_add_field_$name", $parent)) {
	delete $data{$name};
      }
    }
  }
  else {
    $req->user_can('edit_add_child')
      or return $self->add_form($req, $articles, 
				"You cannot create a top-level article");
    for my $name (@columns) {
      if (exists $data{$name} && 
	  !$req->user_can("edit_add_field_$name")) {
	delete $data{$name};
      }
    }
  }
  
  $self->validate_parent(\%data, $articles, $parent, \$msg)
    or return $self->add_form($req, $articles, $msg);

  $self->fill_new_data($req, \%data, $articles);
  my $level = $parent ? $parent->{level}+1 : 1;
  $data{displayOrder} = time;
  $data{titleImage} ||= '';
  $data{imagePos} = 'tr';
  $data{release} = sql_date($data{release}) || now_sqldate();
  $data{expire} = sql_date($data{expire}) || $Constants::D_99;
  unless ($data{template}) {
    $data{template} ||= 
      $self->{cfg}->entry("children of $data{parentid}", 'template');
    $data{template} ||=
      $self->{cfg}->entry("level $level", 'template');
  }
  $data{link} ||= '';
  $data{admin} ||= '';
  if ($parent) {
    $data{threshold} = $parent->{threshold}
      if !defined $data{threshold} || $data{threshold} =~ /^\s*$/;
    $data{summaryLength} = $parent->{summaryLength}
      if !defined $data{summaryLength} || $data{summaryLength} =~ /^\s*$/;
  }
  else {
    $data{threshold} = $self->{cfg}->entry("level $level", 'threshold', 5)
      if !defined $data{threshold} || $data{threshold} =~ /^\s*$/;
    $data{summaryLength} = 200
      if !defined $data{summaryLength} || $data{summaryLength} =~ /^\s*$/;
  }
  $data{generator} = $self->generator;
  $data{lastModified} = now_sqldate();
  $data{level} = $level;
  $data{listed} = 1 unless defined $data{listed};

  shift @columns;
  my $article = $table_object->add(@data{@columns});

  # we now have an id - generate the links

  my $cgi_uri = $self->{cfg}->entry('uri', 'cgi', '/cgi-bin');
  $article->setAdmin("$cgi_uri/admin/admin.pl?id=$article->{id}");
  $article->setLink($self->make_link($article));
  $article->save();

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  my $r = $cgi->param('r');
  if ($r) {
    $r .= ($r =~ /\?/) ? '&' : '?';
    $r .= "id=$article->{id}";
  }
  else {
    my $urlbase = $self->{cfg}->entryVar('site', 'url');
    $r = $urlbase . $article->{admin};
  }
  return BSE::Template->get_refresh($r, $self->{cfg});

}

sub fill_old_data {
  my ($self, $req, $article, $data) = @_;

  if (exists $data->{body}) {
    $data->{body} =~ s/\x0D\x0A/\n/g;
    $data->{body} =~ tr/\r/\n/;
  }
  for my $col (Article->columns) {
    next if $col =~ /^custom/;
    $article->{$col} = $data->{$col}
      if exists $data->{$col} && $col ne 'id' && $col ne 'parentid';
  }
  custom_class($self->{cfg})
    ->article_fill_old($article, $data, $self->typename);

  return 1;
}

sub save {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_save => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to save this article");
  
  my $cgi = $req->cgi;
  my %data;
  for my $name ($article->columns) {
    $data{$name} = $cgi->param($name) 
      if defined($cgi->param($name)) and $name ne 'id' && $name ne 'parentid'
	&& $req->user_can("edit_field_edit_$name", $article);
  }
  # possibly this needs tighter error checking
  $data{flags} = join '', sort $cgi->param('flags')
    if $req->user_can("edit_field_edit_flags", $article);
  my %errors;
  $self->validate_old($article, \%data, $articles, \%errors)
    or return $self->edit_form($req, $article, $articles, undef, \%errors);
  $self->save_thumbnail($cgi, $article, \%data)
    if $req->user_can('edit_field_edit_thumbImage', $article);
  $self->fill_old_data($req, $article, \%data);
  if (exists $article->{template} &&
      $article->{template} =~ m|\.\.|) {
    my $msg = "Please only select templates from the list provided";
    return $self->edit_form($req, $article, $articles, $msg);
  }

  # reparenting
  my $newparentid = $cgi->param('parentid');
  if ($newparentid && $req->user_can('edit_field_edit_parentid', $article)) {
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
	  if ($article->{id} == $newparentid 
	      || $self->is_descendant($article->{id}, $newparentid, $articles)) {
	    my $msg = "Cannot become a child of itself or of a descendant";
	    return $self->edit_form($req, $article, $articles, $msg);
	  }
	  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
	  if ($self->is_descendant($article->{id}, $shopid, $articles)) {
	    my $msg = "Cannot become a descendant of the shop";
	    return $self->edit_form($req, $article, $articles, $msg);
	  }
	  my $msg;
	  $self->reparent($article, $newparentid, $articles, \$msg)
	    or return $self->edit_form($req, $article, $articles, $msg);
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
      my $msg;
      $self->reparent($article, -1, $articles, \$msg)
	or return $self->edit_form($req, $article, $articles, $msg);
    }
  }

  $article->{listed} = $cgi->param('listed')
    if defined $cgi->param('listed') && 
      $req->user_can('edit_field_edit_listed', $article);
  $article->{release} = sql_date($cgi->param('release'))
    if defined $cgi->param('release') && 
      $req->user_can('edit_field_edit_release', $article);
  
  $article->{expire} = sql_date($cgi->param('expire')) || $Constants::D_99
    if defined $cgi->param('expire') && 
      $req->user_can('edit_field_edit_expire', $article);
  $article->{lastModified} =  now_sqldate();
  my $link_titles = $self->{cfg}->entryBool('basic', 'link_titles', 0);
  if ($article->{id} != 1 && $article->{link} && $link_titles) {
    (my $extra = lc $article->{title}) =~ tr/a-z0-9/_/sc;
    my $article_uri = $self->{cfg}->entry('uri', 'articles', '/a');
    $article->{link} = "$article_uri/$article->{id}.html/$extra";
  }

  $article->save();

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, undef, 'Article saved');
}

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

sub reparent {
  my ($self, $article, $newparentid, $articles, $rmsg) = @_;

  my $newlevel;
  if ($newparentid == -1) {
    $newlevel = 1;
  }
  else {
    my $parent = $articles->getByPkey($newparentid);
    unless ($parent) {
      $$rmsg = "Cannot get new parent article";
      return;
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

  return 1;
}

# tests if $desc is a descendant of $art
# where both are article ids
sub is_descendant {
  my ($self, $art, $desc, $articles) = @_;
  
  my @check = ($art);
  while (@check) {
    my $parent = shift @check;
    $parent == $desc and return 1;
    my @kids = $articles->getBy(parentid=>$parent);
    push @check, map $_->{id}, @kids;
  }

  return 0;
}

sub save_thumbnail {
  my ($self, $cgi, $original, $newdata) = @_;

  unless ($original) {
    @$newdata{qw/thumbImage thumbWidth thumbHeight/} = ('', 0, 0);
  }
  my $imagedir = $self->{cfg}->entry('paths', 'images', $Constants::IMAGEDIR);
  if ($cgi->param('remove_thumb') && $original && $original->{thumbImage}) {
    unlink("$imagedir/$original->{thumbImage}");
    @$newdata{qw/thumbImage thumbWidth thumbHeight/} = ('', 0, 0);
  }
  my $image = $cgi->param('thumbnail');
  if ($image && -s $image) {
    # where to put it...
    my $name = '';
    $image =~ /([\w.-]+)$/ and $name = $1;
    my $filename = time . "_" . $name;

    use Fcntl;
    my $counter = "";
    $filename = time . '_' . $counter . '_' . $name
      until sysopen( OUTPUT, "$imagedir/$filename", 
                     O_WRONLY| O_CREAT| O_EXCL)
        || ++$counter > 100;

    fileno(OUTPUT) or die "Could not open image file: $!";
    binmode OUTPUT;
    my $buffer;

    #no strict 'refs';

    # read the image in from the browser and output it to our 
    # output filehandle
    print STDERR "\$image ",ref $image,"\n";
    seek $image, 0, 0;
    print OUTPUT $buffer while sysread $image, $buffer, 1024;

    close OUTPUT
      or die "Could not close image output file: $!";

    use Image::Size;

    if ($original && $original->{thumbImage}) {
      #unlink("$imagedir/$original->{thumbImage}");
    }
    @$newdata{qw/thumbWidth thumbHeight/} = imgsize("$imagedir/$filename");
    $newdata->{thumbImage} = $filename;
  }
}

sub child_types {
  my ($self, $article) = @_;

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  if ($article && $article->{id} && $article->{id} == $shopid) {
    return ( 'BSE::Edit::Catalog' );
  }
  return ( 'BSE::Edit::Article' );
}

sub add_stepkid {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_stepkid_add => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to add step children to this article");

  my $cgi = $req->cgi;
  require 'BSE/Admin/StepParents.pm';
  eval {
    my $childId = $cgi->param('stepkid');
    defined $childId
      or die "No stepkid supplied to add_stepkid";
    $childId =~ /^\d+$/
      or die "Invalid stepkid supplied to add_stepkid";
    my $child = $articles->getByPkey($childId)
      or die "Article $childId not found";

    $req->user_can(edit_stepparent_add => $child)
      or die "You don't have access to add a stepparent to that article\n";
    
    use BSE::Util::Valid qw/valid_date/;
    my $release = $cgi->param('release');
    valid_date($release) or $release = undef;
    my $expire = $cgi->param('expire');
    valid_date($expire) or $expire = undef;
  
    my $newentry = 
      BSE::Admin::StepParents->add($article, $child, $release, $expire);
  };
  if ($@) {
    return $self->edit_form($req, $article, $articles, $@);
  }

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'step', 'Stepchild added');
}

sub del_stepkid {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_stepkid_delete => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to delete stepchildren from this article");

  my $cgi = $req->cgi;
  require 'BSE/Admin/StepParents.pm';
  eval {
    my $childId = $cgi->param('stepkid');
    defined $childId
      or die "No stepkid supplied to add_stepkid";
    $childId =~ /^\d+$/
      or die "Invalid stepkid supplied to add_stepkid";
    my $child = $articles->getByPkey($childId)
      or die "Article $childId not found";

    $req->user_can(edit_stepparent_delete => $child)
      or die "You cannot remove stepparents from that article\n";
    
    BSE::Admin::StepParents->del($article, $child);
  };
  
  if ($@) {
    return $self->edit_form($req, $article, $articles, $@);
  }
  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'step', 'Stepchild deleted');
}

sub save_stepkids {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_stepkid_save => $article)
    or return $self->edit_form($req, $article, $articles,
			       "No access to save stepkid data for this article");

  my $cgi = $req->cgi;
  require 'BSE/Admin/StepParents.pm';
  my @stepcats = OtherParents->getBy(parentId=>$article->{id});
  my %stepcats = map { $_->{parentId}, $_ } @stepcats;
  my %datedefs = ( release => '2000-01-01', expire=>'2999-12-31' );
  for my $stepcat (@stepcats) {
    $req->user_can(edit_stepparent_save => $stepcat->{childId})
      or next;
    for my $name (qw/release expire/) {
      my $date = $cgi->param($name.'_'.$stepcat->{childId});
      if (defined $date) {
	if ($date eq '') {
	  $date = $datedefs{$name};
	}
	elsif (valid_date($date)) {
	  use BSE::Util::SQL qw/date_to_sql/;
	  $date = date_to_sql($date);
	}
	else {
	  return $self->refresh($article, $cgi, '', "Invalid date '$date'");
	}
	$stepcat->{$name} = $date;
      }
    }
    eval {
      $stepcat->save();
    };
    $@ and return $self->refresh($article, $cgi, '', $@);
  }
  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'step', 'Stepchild information saved');
}

sub add_stepparent {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_stepparent_add => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to add stepparents to this article");

  my $cgi = $req->cgi;
  require 'BSE/Admin/StepParents.pm';
  eval {
    my $step_parent_id = $cgi->param('stepparent');
    defined($step_parent_id)
      or die "No stepparent supplied to add_stepparent";
    int($step_parent_id) eq $step_parent_id
      or die "Invalid stepcat supplied to add_stepcat";
    my $step_parent = $articles->getByPkey($step_parent_id)
      or die "Parent $step_parent_id not found\n";

    $req->user_can(edit_stepkid_add => $step_parent)
      or die "You don't have access to add a stepkid to that article\n";

    my $release = $cgi->param('release');
    defined $release
      or $release = "01/01/2000";
    use BSE::Util::Valid qw/valid_date/;
    $release eq '' or valid_date($release)
      or die "Invalid release date";
    my $expire = $cgi->param('expire');
    defined $expire
      or $expire = '31/12/2999';
    $expire eq '' or valid_date($expire)
      or die "Invalid expire data";
  
    my $newentry = 
      BSE::Admin::StepParents->add($step_parent, $article, $release, $expire);
  };
  $@ and return $self->refresh($article, $cgi, 'step', $@);

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'stepparents', 'Stepparent added');
}

sub del_stepparent {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_stepparent_delete => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You cannot remove stepparents from that article");

  my $cgi = $req->cgi;
  require 'BSE/Admin/StepParents.pm';
  my $step_parent_id = $cgi->param('stepparent');
  defined($step_parent_id)
    or return $self->refresh($article, $cgi, 'stepparents', 
			     "No stepparent supplied to add_stepcat");
  int($step_parent_id) eq $step_parent_id
    or return $self->refresh($article, $cgi, 'stepparents', 
			     "Invalid stepparent supplied to add_stepparent");
  my $step_parent = $articles->getByPkey($step_parent_id)
    or return $self->refresh($article, $cgi, 'stepparent', 
			     "Stepparent $step_parent_id not found");

  $req->user_can(edit_stepkid_delete => $step_parent)
    or die "You don't have access to remove the stepkid from that article\n";

  eval {
    BSE::Admin::StepParents->del($step_parent, $article);
  };
  $@ and return $self->refresh($article, $cgi, 'stepparents', $@);

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'stepparents', 'Stepparent deleted');
}

sub save_stepparents {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_stepparent_save => $article)
    or return $self->edit_form($req, $article, $articles,
			       "No access to save stepparent data for this artice");

  my $cgi = $req->cgi;

  require 'BSE/Admin/StepParents.pm';
  my @stepparents = OtherParents->getBy(childId=>$article->{id});
  my %stepparents = map { $_->{parentId}, $_ } @stepparents;
  my %datedefs = ( release => '2000-01-01', expire=>'2999-12-31' );
  for my $stepparent (@stepparents) {
    $req->user_can(edit_stepkid_save => $stepparent->{parentId})
      or next;
    for my $name (qw/release expire/) {
      my $date = $cgi->param($name.'_'.$stepparent->{parentId});
      if (defined $date) {
	if ($date eq '') {
	  $date = $datedefs{$name};
	}
	elsif (valid_date($date)) {
	  use BSE::Util::SQL qw/date_to_sql/;
	  $date = date_to_sql($date);
	}
	else {
	  return $self->refresh($article, $cgi, "Invalid date '$date'");
	}
	$stepparent->{$name} = $date;
      }
    }
    eval {
      $stepparent->save();
    };
    $@ and return $self->refresh($article, $cgi, '', $@);
  }

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'stepparents', 
			'Stepparent information saved');
}

sub refresh {
  my ($self, $article, $cgi, $name, $message, $extras) = @_;

  my $url = $cgi->param('r');
  unless ($url) {
    my $urlbase = $self->{cfg}->entryVar('site', 'url');
    $url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}";
    $url .= "&message=" . CGI::escape($message) if $message;
    if ($cgi->param('_t')) {
      $url .= "&_t=".CGI::escape($cgi->param('_t'));
    }
    $url .= $extras if defined $extras;
    my $cgiextras = $cgi->param('e');
    $url .= "#$name" if $name;
  }

  return BSE::Template->get_refresh($url, $self->{cfg});
}

sub show_images {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  my %acts;
  %acts = $self->low_edit_tags(\%acts, $req, $article, $articles, $msg, $errors);
  my $template = 'admin/article_img';

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

sub save_image_changes {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_images_save => $article)
    or return $self->show_images($req, $article, $articles,
				 "You don't have access to save image information for this article");

  my $cgi = $req->cgi;
  my $image_pos = $cgi->param('imagePos');
  if ($image_pos 
      && $image_pos =~ /^(?:tl|tr|bl|br)$/
      && $image_pos ne $article->{imagePos}) {
    $article->{imagePos} = $image_pos;
    $article->save;
  }
  my @images = $article->images;

  my $changed;
  my @alt = $cgi->param('alt');
  if (@alt) {
    ++$changed;
    for my $index (0..$#images) {
      $index < @alt or last;
      $images[$index]{alt} = $alt[$index];
    }
  }
  my @urls = $cgi->param('url');
  if (@urls) {
    ++$changed;
    for my $index (0..$#images) {
      $index < @urls or next;
      $images[$index]{url} = $urls[$index];
    }
  }
  if ($changed) {
    for my $image (@images) {
      $image->save;
    }
  }

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;


  return $self->refresh($article, $cgi, undef, 'Image information saved', 
			'&showimages=1');
}

sub add_image {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_images_add => $article)
    or return $self->show_images($req, $article, $articles,
				 "You don't have access to add new images to this article");

  my $cgi = $req->cgi;

  my $image = $cgi->param('image');
  unless ($image) {
    return $self->show_images($req, $article, $articles,
			      'Enter or select the name of an image file on your machine', 
			      { image => 'Please enter an image filename' });
  }
  if (-z $image) {
    return $self->show_images($req, $article, $articles,
			      'Image file is empty',
			     { image => 'Image file is empty' });
  }
  my $imagename = $image;
  $imagename .= ''; # force it into a string
  my $basename = '';
  $imagename =~ /([\w.-]+)$/ and $basename = $1;

  # create a filename that we hope is unique
  my $filename = time. '_'. $basename;

  # for the sysopen() constants
  use Fcntl;

  my $imagedir = $req->cfg->entry('paths', 'images', $Constants::IMAGEDIR);
  # loop until we have a unique filename
  my $counter="";
  $filename = time. '_' . $counter . '_' . $basename 
    until sysopen( OUTPUT, "$imagedir/$filename", O_WRONLY| O_CREAT| O_EXCL)
      || ++$counter > 100;

  fileno(OUTPUT) or die "Could not open image file: $!";

  # for OSs with special text line endings
  binmode OUTPUT;

  my $buffer;

  no strict 'refs';

  # read the image in from the browser and output it to our output filehandle
  print OUTPUT $buffer while read $image, $buffer, 1024;

  # close and flush
  close OUTPUT
    or die "Could not close image file $filename: $!";

  use Image::Size;


  my($width,$height) = imgsize("$imagedir/$filename");

  my $alt = $cgi->param('altIn');
  defined $alt or $alt = '';
  my $url = $cgi->param('url');
  defined $url or $url = '';
  my %image =
    (
     articleId => $article->{id},
     image => $filename,
     alt=>$alt,
     width=>$width,
     height => $height,
     url => $url,
     displayOrder=>time,
    );
  require Images;
  my @cols = Image->columns;
  shift @cols;
  my $imageobj = Images->add(@image{@cols});

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, undef, 'New image added',
			'&showimages=1');
}

# remove an image
sub remove_img {
  my ($self, $req, $article, $articles, $imageid) = @_;

  $req->user_can(edit_images_delete => $article)
    or return $self->show_images($req, $article, $articles,
				 "You don't have access to delete images from this article");

  $imageid or die;

  my @images = $article->images();
  my ($image) = grep $_->{id} == $imageid, @images
    or return $self->show_images($req, $article, $articles, "No such image");
  my $imagedir = $req->cfg->entry('paths', 'images', $Constants::IMAGEDIR);
  unlink "$imagedir$image->{image}";
  $image->remove;

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $req->cgi, undef, 'Image removed',
			'&showimages=1');
}

sub move_img_up {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_images_reorder => $article)
    or return $self->show_images($req, $article, $articles,
				 "You don't have access to reorder images in this article");

  my $imageid = $req->cgi->param('imageid');
  my @images = $article->images;
  my ($imgindex) = grep $images[$_]{id} == $imageid, 0..$#images
    or return $self->show_images($req, $article, $articles, "No such image");
  $imgindex > 0
    or return $self->show_images($req, $article, $articles, "Image is already at the top");
  my ($to, $from) = @images[$imgindex-1, $imgindex];
  ($to->{displayOrder}, $from->{displayOrder}) =
    ($from->{displayOrder}, $to->{displayOrder});
  $to->save;
  $from->save;

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $req->cgi, undef, 'Image moved',
			'&showimages=1');
}

sub move_img_down {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_images_reorder => $article)
    or return $self->show_images($req, $article, $articles,
				 "You don't have access to reorder images in this article");

  my $imageid = $req->cgi->param('imageid');
  my @images = $article->images;
  my ($imgindex) = grep $images[$_]{id} == $imageid, 0..$#images
    or return $self->show_images($req, $article, $articles, "No such image");
  $imgindex < $#images
    or return $self->show_images($req, $article, $articles, "Image is already at the end");
  my ($to, $from) = @images[$imgindex+1, $imgindex];
  ($to->{displayOrder}, $from->{displayOrder}) =
    ($from->{displayOrder}, $to->{displayOrder});
  $to->save;
  $from->save;

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $req->cgi, undef, 'Image moved', 
			'&showimages=1');
}

sub get_article {
  my ($self, $articles, $article) = @_;

  return $article;
}

sub table_object {
  my ($self, $articles) = @_;

  $articles;
}

my %types =
  (
   qw(
   pdf  application/pdf
   txt  text/plain
   htm  text/html
   html text/html
   gif  image/gif
   jpg  image/jpeg
   jpeg image/jpeg
   doc  application/msword
   rtf  application/rtf
   zip  application/zip
   png  image/png
   bmp  image/bmp
   tif  image/tiff
   tiff image/tiff
   sgm  text/sgml
   sgml text/sgml
   xml  text/xml
   mov  video/quicktime
   )
  );

sub _refresh_filelist {
  my ($self, $req, $article, $msg) = @_;

  return $self->refresh($article, $req->cgi, undef, $msg, '&filelist=1');
}

sub filelist {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  my %acts;
  %acts = $self->low_edit_tags(\%acts, $req, $article, $articles, $msg, $errors);
  my $template = 'admin/filelist';

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

sub fileadd {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can(edit_files_add => $article)
    or return $self->filelist($req, $article, $articles,
			      "You don't have access to add files to this article");

  my %file;
  my $cgi = $req->cgi;
  require ArticleFile;
  my @cols = ArticleFile->columns;
  shift @cols;
  for my $col (@cols) {
    if (defined $cgi->param($col)) {
      $file{$col} = $cgi->param($col);
    }
  }
  
  $file{forSale} = 0 + exists $file{forSale};
  $file{articleId} = $article->{id};
  $file{download} = 0 + exists $file{download};
  $file{requireUser} = 0 + exists $file{requireUser};

  my $downloadPath = $self->{cfg}->entryVar('paths', 'downloads');

  # build a filename
  my $file = $cgi->param('file');
  unless ($file) {
    return $self->filelist($req, $article, $articles,
			   "Enter or select the name of a file on your machine",
			  { file => 'Please enter a filename' });
  }
  if (-z $file) {
    return $self->filelist($req, $article, $articles,
			   "File is empty",
			   { file => 'File is empty' });
  }

  unless ($file{contentType}) {
    unless ($file =~ /\.([^.]+)$/) {
      $file{contentType} = "application/octet-stream";
    }
    unless ($file{contentType}) {
      my $ext = lc $1;
      my $type = $types{$ext};
      unless ($type) {
	$type = $self->{cfg}->entry('extensions', $ext)
	  || $self->{cfg}->entry('extensions', ".$ext")
	    || "application/octet-stream";
      }
      $file{contentType} = $type;
    }
  }
  
  my $basename = '';
  $file =~ /([\w.-]+)$/ and $basename = $1;

  my $filename = time. '_'. $basename;

  # for the sysopen() constants
  use Fcntl;

  # loop until we have a unique filename
  my $counter="";
  $filename = time. '_' . $counter . '_' . $basename 
    until sysopen( OUTPUT, "$downloadPath/$filename", 
		   O_WRONLY| O_CREAT| O_EXCL)
      || ++$counter > 100;

  fileno(OUTPUT) or die "Could not open file: $!";

  # for OSs with special text line endings
  binmode OUTPUT;

  my $buffer;

  no strict 'refs';

  # read the image in from the browser and output it to our output filehandle
  print OUTPUT $buffer while read $file, $buffer, 8192;

  # close and flush
  close OUTPUT
    or die "Could not close file $filename: $!";

  use BSE::Util::SQL qw/now_datetime/;
  $file{filename} = $filename;
  $file{displayName} = $basename;
  $file{sizeInBytes} = -s $file;
  $file{displayOrder} = time;
  $file{whenUploaded} = now_datetime();

  require ArticleFiles;
  my $fileobj = ArticleFiles->add(@file{@cols});

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->_refresh_filelist($req, $article, 'New file added');
}

sub fileswap {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can('edit_files_reorder', $article)
    or return $self->filelist($req, $article, $articles,
			   "You don't have access to reorder files in this article");

  my $cgi = $req->cgi;
  my $id1 = $cgi->param('file1');
  my $id2 = $cgi->param('file2');

  if ($id1 && $id2) {
    my @files = $article->files;
    
    my ($file1) = grep $_->{id} == $id1, @files;
    my ($file2) = grep $_->{id} == $id2, @files;
    
    if ($file1 && $file2) {
      ($file1->{displayOrder}, $file2->{displayOrder})
	= ($file2->{displayOrder}, $file1->{displayOrder});
      $file1->save;
      $file2->save;
    }
  }

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->_refresh_filelist($req, $article, 'File moved');
}

sub filedel {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can('edit_files_delete', $article)
    or return $self->filelist($req, $article, $articles,
			   "You don't have access to delete files from this article");

  my $cgi = $req->cgi;
  my $fileid = $cgi->param('file');
  if ($fileid) {
    my @files = $article->files;

    my ($file) = grep $_->{id} == $fileid, @files;

    if ($file) {
      my $downloadPath = $req->cfg->entryErr('paths', 'downloads');
      my $filename = $downloadPath . "/" . $file->{filename};
      my $debug_del = $req->cfg->entryBool('debug', 'file_unlink', 0);
      if ($debug_del) {
	unlink $filename
	  or print STDERR "Error deleting $filename: $!\n";
      }
      else {
	unlink $filename;
      }
      $file->remove();
    }
  }

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->_refresh_filelist($req, $article, 'File deleted');
}

sub filesave {
  my ($self, $req, $article, $articles) = @_;

  $req->user_can('edit_files_save', $article)
    or return $self->filelist($req, $article, $articles,
			   "You don't have access to save file information for this article");
  my @files = $article->files;

  my $cgi = $req->cgi;
  for my $file (@files) {
    if (defined $cgi->param("description_$file->{id}")) {
      $file->{description} = $cgi->param("description_$file->{id}");
      if (my $type = $cgi->param("contentType_$file->{id}")) {
	$file->{contentType} = $type;
      }
      $file->{download} = 0 + defined $cgi->param("download_$file->{id}");
      $file->{forSale} = 0 + defined $cgi->param("forSale_$file->{id}");
      $file->{requireUser} = 0 + defined $cgi->param("requireUser_$file->{id}");
      $file->save;
    }
  }

  use Util 'generate_article';
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->_refresh_filelist($req, $article, 'File information saved');
}

sub can_remove {
  my ($self, $req, $article, $articles, $rmsg) = @_;

  unless ($req->user_can('edit_delete_article', $article, $rmsg)) {
    $$rmsg ||= "Access denied";
    return;
  }

  if ($articles->children($article->{id})) {
    $$rmsg = "This article has children.  You must delete the children first (or change their parents)";
    return;
  }
  if (grep $_ == $article->{id}, @Constants::NO_DELETE) {
    $$rmsg = "Sorry, these pages are essential to the site structure - they cannot be deleted";
    return;
  }
  if ($article->{id} == $Constants::SHOPID) {
    $$rmsg = "Sorry, these pages are essential to the store - they cannot be deleted - you may want to hide the the store instead.";
    return;
  }

  return 1;
}

sub remove {
  my ($self, $req, $article, $articles) = @_;

  my $why_not;
  unless ($self->can_remove($req, $article, $articles, \$why_not)) {
    return $self->edit_form($req, $article, $articles, $why_not);
  }

  require Images;
  my @images = Images->getBy(articleId=>$article->{id});
  my $imagedir = $self->{cfg}->entry('paths', 'images', $Constants::IMAGEDIR);
  for my $image (@images) {
    unlink("$imagedir/$image->{image}");
    $image->remove();
  }
  
  # remove any step(child|parent) links
  require OtherParents;
  my @steprels = OtherParents->anylinks($article->{id});
  for my $link (@steprels) {
    $link->remove();
  }
  
  my $parentid = $article->{parentid};
  $article->remove;
  my $url = $req->cgi->param('r');
  unless ($url) {
    my $urlbase = $self->{cfg}->entryVar('site', 'url');
    $url = "$urlbase$ENV{SCRIPT_NAME}?id=$parentid";
    $url .= "&message=Article+deleted";
  }
  return BSE::Template->get_refresh($url, $self->{cfg});
}

sub unhide {
  my ($self, $req, $article, $articles) = @_;

  if ($req->user_can(edit_field_edit_listed => $article)
      && $req->user_can(edit_save => $article)) {
    $article->{listed} = 1;
    $article->save;

    use Util 'generate_article';
    generate_article($articles, $article) if $Constants::AUTO_GENERATE;
  }
  return $self->refresh($article, $req->cgi, undef, 'Article unhidden');
}

sub hide {
  my ($self, $req, $article, $articles) = @_;

  if ($req->user_can(edit_field_edit_listed => $article)
      && $req->user_can(edit_save => $article)) {
    $article->{listed} = 0;
    $article->save;

    use Util 'generate_article';
    generate_article($articles, $article) if $Constants::AUTO_GENERATE;
  }
  my $r = $req->cgi->param('r');
  unless ($r) {
    $r = $req->cfg->entryVar('site', 'url') . "/cgi-bin/admin/add.pl?id=" . $article->{parentid};
  }
  return $self->refresh($article, $req->cgi, undef, 'Article hidden');
}

sub default_value {
  my ($self, $req, $article, $col) = @_;

  if ($article->{parentid}) {
    my $section = "children of $article->{parentid}";
    my $value = $req->cfg->entry($section, $col);
    if (defined $value) {
    }
  }
  my $section = "level $article->{level}";
  my $value = $req->cfg->entry($section, $col);
  defined($value) and return encode_entities($value);
  
  return '';
}

sub flag_sections {
  return ( 'article flags' );
}

sub flags {
  my ($self) = @_;

  my $cfg = $self->{cfg};

  my @sections = $self->flag_sections;

  my %flags = map $cfg->entriesCS($_), reverse @sections;
  my @valid = grep /^\w$/, keys %flags;
  
  return map +{ id => $_, desc => $flags{$_} },
    sort { lc($flags{$a}) cmp lc($flags{$b}) }@valid;
}

1;

=head1 NAME

  BSE::Edit::Article - editing functionality for BSE articles

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 REVISION 

$Revision$

=cut
