package BSE::Edit::Article;
use strict;
use base qw(BSE::Edit::Base);
use BSE::Util::Tags qw(tag_error_img tag_article tag_object);
use BSE::Util::SQL qw(now_sqldate now_sqldatetime);
use BSE::Permissions;
use BSE::Util::HTML qw(:default popup_menu);
use BSE::Arrows;
use BSE::CfgInfo qw(custom_class admin_base_url cfg_image_dir cfg_dist_image_uri cfg_image_uri);
use BSE::Util::Iterate;
use BSE::Template;
use BSE::Util::ContentType qw(content_type);
use BSE::Regen 'generate_article';
use DevHelp::Date qw(dh_parse_date dh_parse_sql_date);
use List::Util qw(first);
use constant MAX_FILE_DISPLAYNAME_LENGTH => 255;
use constant ARTICLE_CUSTOM_FIELDS_CFG => "article custom fields";

our $VERSION = "1.045";

=head1 NAME

  BSE::Edit::Article - editing functionality for BSE articles

=head1 DESCRIPTION

Provides the base article editing functionality.

This is badly organized and documented.

=head1 METHODS

=over

=cut

sub not_logged_on {
  my ($self, $req) = @_;

  if ($req->is_ajax) {
    # AJAX/Prototype request
    return $req->json_content
      (
       {
	success => 0,
	message => "Access forbidden: user not logged on",
	errors => {},
	error_code => "LOGON",
       }
      );
  }
  elsif ($req->cgi->param('_service')) {
    return
      {
       content => 'Access Forbidden: login timed out',
       headers => [
		   "Status: 403", # forbidden
		  ],
      };
  }
  else {
    BSE::Template->get_refresh($req->url('logon'), $req->cfg);
  }
}

sub article_dispatch {
  my ($self, $req, $article, $articles) = @_;

  BSE::Permissions->check_logon($req)
    or return $self->not_logged_on($req);

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

  my $mymsg;
  my $article = $self->_dummy_article($req, $articles, \$mymsg);
  unless ($article) {
    require BSE::Edit::Site;
    my $site = BSE::Edit::Site->new(cfg=>$req->cfg, db=> BSE::DB->single);
    return $site->edit_sections($req, $articles, $mymsg);
  }

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
  return $self->$method($req, $article, $articles);
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
     a_edit_image => 'req_edit_image',
     a_save_image => 'req_save_image',
     a_order_images => 'req_order_images',
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
     a_edit_file => 'req_edit_file',
     a_save_file => 'req_save_file',
     hide => 'hide',
     unhide => 'unhide',
     a_thumb => 'req_thumb',
     a_ajax_get => 'req_ajax_get',
     a_ajax_save_body => 'req_ajax_save_body',
     a_ajax_set => 'req_ajax_set',
     a_filemeta => 'req_filemeta',
     a_csrfp => 'req_csrfp',
     a_tree => 'req_tree',
     a_article => 'req_article',
     a_config => 'req_config',
     a_restepkid => 'req_restepkid',
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
     a_csrfp => 'req_csrfp',
     a_config => 'req_config',
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
  escape_html($value);
}

sub tag_hash_mbcs {
  my ($object, $args) = @_;

  my $value = $object->{$args};
  defined $value or $value = '';
  if ($value =~ /\cJ/ && $value =~ /\cM/) {
    $value =~ tr/\cM//d;
  }
  escape_html($value, '<>&"');
}

sub tag_art_type {
  my ($level, $cfg) = @_;

  escape_html($cfg->entry('level names', $level, 'Article'));
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

  my $shopid = $self->cfg->entryErr('articles', 'shop');

  return $article->{parentid} && $parent &&
    ($article->{parentid} == $shopid || 
     $parent->{generator} eq 'Generate::Catalog');
}

sub possible_parents {
  my ($self, $article, $articles, $req) = @_;

  my %labels;
  my @values;

  my $shopid = $self->cfg->entryErr('articles', 'shop');
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
	  $labels{-1} = $req->catmsg("msg:bse/admin/edit/uplabelsect");
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
    return popup_menu(-name=>'listed',
		      -values=>\@values,
		      -labels=>\%labels,
		      -default=>$article->{listed});
  }
  else {
    my ($values, $labels) = $self->possible_parents($article, $articles, $req);
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

sub tag_checked {
  my ($arg, $acts, $funcname, $templater) = @_;
  my ($func, $args) = split ' ', $arg, 2;
  return $templater->perform($acts, $func, $args) ? 'checked' : '';
}

sub iter_get_images {
  my ($self, $article) = @_;

  $article->{id} or return;
  $self->get_images($article);
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

  my @templates = sort { $a->{name} cmp $b->{name} } $self->templates_long($article);
  my $default;
  if ($article->{template} && grep $_->{name} eq $article->{template}, @templates) {
    $default = $article->{template};
  }
  else {
    my @template_names = map $_->{name}, @templates;
    $default = $self->default_template($article, $cfg, \@template_names);
  }
  my %labels =
    (
     map
     { ;
       $_->{name} => 
       $_->{name} eq $_->{description}
	 ? $_->{name}
	   : "$_->{description} ($_->{name})"
     } @templates
    );
  return popup_menu(-name => 'template',
		    -values => [ map $_->{name}, @templates ],
		    -labels => \%labels,
		    -default => $default,
		    -override => 1);
}

sub title_images {
  my ($self, $article) = @_;

  my @title_images;
  my $imagedir = cfg_image_dir($self->cfg);
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
    if (my $dirs = $self->cfg->entry($section, 'template_dirs')) {
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

sub categories {
  my ($self, $articles) = @_;

  return $articles->categories;
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

  require OtherParents;
  my @stepkids = OtherParents->getBy(parentId=>$article->{id}) if $article->{id};
  %$step_kids = map { $_->{childId} => $_ } @stepkids;
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
  my $step_kid = $step_kids->{$kid->{id}}
    or return '';
  #use Data::Dumper;
  #print STDERR "found kid (want $arg): ", Dumper($kid), Dumper($step_kid);
  escape_html($step_kid->{$arg});
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
  my $url = $ENV{SCRIPT_NAME} . "?id=$article->{id}";
  if ($cgi->param('_t')) {
    $url .= "&_t=".$cgi->param('_t');
  }
  $url .= $urladd;
  $url .= "#step";
  my $down_url = '';
  if ($$rallkids_index < $#$allkids) {
    $down_url = "$cgi_uri/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids->[$$rallkids_index]{id}&other=$allkids->[$$rallkids_index+1]{id}";
  }
  my $up_url = '';
  if ($$rallkids_index > 0) {
    $up_url = "$cgi_uri/admin/move.pl?stepparent=$article->{id}&d=swap&id=$allkids->[$$rallkids_index]{id}&other=$allkids->[$$rallkids_index-1]{id}";
  }
  
  return make_arrows($req->cfg, $down_url, $up_url, $url, $img_prefix);
}

sub possible_stepkids {
  my ($req, $article, $articles, $stepkids) = @_;

  $req->user_can(edit_stepkid_add => $article)
    or return;

  $article->{id} == -1
    and return;

  my @possible = sort { lc $a->{title} cmp lc $b->{title} }
     $article->possible_stepchildren;
  if ($req->access_control && $req->cfg->entry('basic', 'access_filter_steps', 0)) {
    @possible = grep $req->user_can(edit_stepparent_add => $_->{id}), @possible;
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
    popup_menu(-name=>'stepkid',
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

  require OtherParents;
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
  escape_html($targs->[$$rindex]{$arg});
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
  my $images_uri = cfg_dist_image_uri();
  my $html = '';
  my $url = $ENV{SCRIPT_NAME} . "?id=$article->{id}";
  if ($cgi->param('_t')) {
    $url .= "&_t=".$cgi->param('_t');
  }
  $url .= $urladd;
  $url .= "#stepparents";
  my $blank = qq!<img src="$images_uri/trans_pixel.gif" width="17" height="13" border="0" align="absbottom" alt="" />!;
  my $down_url = '';
  if ($$rindex < $#$stepparents) {
    $down_url = "$cgi_uri/admin/move.pl?stepchild=$article->{id}&id=$stepparents->[$$rindex]{parentId}&d=swap&other=$stepparents->[$$rindex+1]{parentId}";
  }
  my $up_url = '';
  if ($$rindex > 0) {
    $up_url = "$cgi_uri/admin/move.pl?stepchild=$article->{id}&id=$stepparents->[$$rindex]{parentId}&d=swap&other=$stepparents->[$$rindex-1]{parentId}";
  }

  return make_arrows($req->cfg, $down_url, $up_url, $url, $img_prefix);
}

sub _stepparent_possibles {
  my ($req, $article, $articles, $targs) = @_;

  $req->user_can(edit_stepparent_add => $article)
    or return;

  $article->{id} == -1
    and return;

  @$targs = $article->step_parents unless @$targs;
  my %targs = map { $_->{id}, 1 } @$targs;
  my @possibles = $article->possible_stepparents;
  if ($req->access_control && $req->cfg->entry('basic', 'access_filter_steps', 0)) {
    @possibles = grep $req->user_can(edit_stepkid_add => $_->{id}), @possibles;
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
  popup_menu(-name=>'stepparent',
	     -values => [ map $_->{id}, @$possibles ],
	     -labels => { map { $_->{id}, "$_->{title} ($_->{id})" }
			  @$possibles });
}

sub iter_files {
  my ($self, $article) = @_;

  return $self->get_files($article);
}

sub get_files {
  my ($self, $article) = @_;

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
  my $images_uri = cfg_dist_image_uri();
  my $urlbase = admin_base_url($req->cfg);
  my $refresh_url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}";
  my $t = $req->cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $refresh_url .= "&_t=$t";
  }

  $refresh_url .= $urladd;

  my $id = $kids->[$$rindex]{id};
  my $down_url = '';
  if ($$rindex < $#$kids) {
    $down_url = "$cgi_uri/admin/move.pl?id=$id&d=down&edit=1&all=1";
  }
  my $up_url = '';
  if ($$rindex > 0) {
    $up_url = "$cgi_uri/admin/move.pl?id=$id&d=up&edit=1&all=1"
  }

  return make_arrows($req->cfg, $down_url, $up_url, $refresh_url, $img_prefix);
}

sub tag_category {
  my ($self, $articles, $article) = @_;

  my @cats = $self->categories($articles);

  my %labels = map { $_->{id}, $_->{name} } @cats;

  return popup_menu(-name => 'category',
		    -values => [ map $_->{id}, @cats ],
		    -labels => \%labels,
		    -default => $article->{category});
}

sub tag_edit_link {
  my ($cfg, $article, $args, $acts, $funcname, $templater) = @_;
  my ($which, $name) = split / /, $args, 2;
  $name ||= 'Edit';
  my $gen_class;
  if ($acts->{$which} 
      && ($gen_class = $templater->perform($acts, $which, 'generator'))) {
    eval "use $gen_class";
    unless ($@) {
      my $gen = $gen_class->new(top => $article, cfg => $cfg);
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

  my $urlbase = admin_base_url($req->cfg);
  my $url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}";
  my $t = $req->cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $url .= "&_t=$t";
  }
  $url .= $urladd;

  my $image = $images->[$$rindex];
  my $csrfp = $req->get_csrf_token("admin_move_image");
  my $baseurl = "$ENV{SCRIPT_NAME}?id=$article->{id}&imageid=$image->{id}&";
  $baseurl .= "_csrfp=$csrfp&";
  my $down_url = "";
  if ($$rindex < $#$images) {
    $down_url = $baseurl . "moveimgdown=1";
  }
  my $up_url = "";
  if ($$rindex > 0) {
    $up_url = $baseurl . "moveimgup=1";
  }
  return make_arrows($req->cfg, $down_url, $up_url, $url, $img_prefix);
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

  $$rindex >= 0 && $$rindex < @$files
    or return '** movefiles can only be used in the files iterator **';

  my $urlbase = admin_base_url($req->cfg);
  my $url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}$urladd";
  my $t = $req->cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $url .= "&_t=$t";
  }

  my $down_url = "";
  my $csrfp = $req->get_csrf_token("admin_move_file");
  my $baseurl = "$ENV{SCRIPT_NAME}?fileswap=1&id=$article->{id}&";
  $baseurl .= "_csrfp=$csrfp&";
  if ($$rindex < $#$files) {
    $down_url = $baseurl . "file1=$files->[$$rindex]{id}&file2=$files->[$$rindex+1]{id}";
  }
  my $up_url = "";
  if ($$rindex > 0) {
    $up_url = $baseurl . "file1=$files->[$$rindex]{id}&file2=$files->[$$rindex-1]{id}";
  }

  return make_arrows($req->cfg, $down_url, $up_url, $url, $img_prefix);
}

sub tag_old {
  my ($article, $cgi, $args, $acts, $funcname, $templater) = @_;

  my ($col, $func, $funcargs) = split ' ', $args, 3;
  my $value = $cgi->param($col);
  if (defined $value) {
    return escape_html($value);
  }
  else {
    if ($func) {
      return $templater->perform($acts, $func, $funcargs);
    }
    else {
      $value = $article->{$args};
      defined $value or $value = '';
      return escape_html($value);
    }
  }
}

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
      return escape_html($value, '<>&"');
    }
  }
  else {
    my $value = $self->default_value($req, $article, $col);
    defined $value or $value = '';
    return escape_html($value, '<>&"');
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

sub _get_thumbs_class {
  my ($self) = @_;

  $self->{cfg}->entry('editor', 'allow_thumb', 0)
    or return;

  my $class = $self->{cfg}->entry('editor', 'thumbs_class')
    or return;
  
  (my $filename = "$class.pm") =~ s!::!/!g;
  eval { require $filename; };
  if ($@) {
    print STDERR "** Error loading thumbs_class $class ($filename): $@\n";
    return;
  }
  my $obj;
  eval { $obj = $class->new($self->{cfg}) };
  if ($@) {
    print STDERR "** Error creating thumbs objects $class: $@\n";
    return;
  }

  return $obj;
}

sub tag_thumbimage {
  my ($cfg, $thumbs_obj, $current_image, $args) = @_;

  $thumbs_obj or return '';

  $$current_image or return '** no current image **';

  my $imagedir = cfg_image_dir($cfg);

  my $filename = "$imagedir/$$current_image->{image}";
  -e $filename or return "** image file missing **";

  defined $args && $args =~ /\S/
    or $args = "editor";

  my $image = $$current_image;
  return $image->thumb
    (
     geo => $args,
     cfg => $cfg,
     nolink => 1,
    );
}

sub tag_file_display {
  my ($self, $files, $file_index) = @_;

  $$file_index >= 0 && $$file_index < @$files
    or return "* file_display only usable inside a files iterator *";
  my $file = $files->[$$file_index];

  my $disp_type = $self->cfg->entry("editor", "file_display", "");

  return $file->inline
    (
     cfg => $self->cfg,
     field => $disp_type,
    );
}

sub tag_image {
  my ($self, $cfg, $rcurrent, $args) = @_;

  my $im = $$rcurrent
    or return '';

  my ($align, $rest) = split ' ', $args, 2;

  if ($align && exists $im->{$align}) {
    if ($align eq 'src') {
      return escape_html($im->image_url($self->{cfg}));
    }
    else {
      return escape_html($im->{$align});
    }
  }
  else {
    return $im->formatted
      (
       cfg => $cfg,
       align => $align,
       extras => $rest,
      );
  }
}

sub iter_tags {
  my ($self, $article) = @_;

  $article->{id}
    or return;

  return $article->tag_objects;
}

my %base_custom_validation =
  (
   customDate1 =>
   {
    rules => "date",
    htmltype => "text",
    width => 10,
    default => "",
    type => "date",
   },
   customDate2 =>
   {
    rules => "date",
    htmltype => "text",
    width => 10,
    default => "",
    type => "date",
   },
   customStr1 =>
   {
    htmltype => "text",
    default => "",
   },
   customStr2 =>
   {
    htmltype => "text",
    default => "",
   },
   customInt1 =>
   {
    rules => "integer",
    htmltype => "text",
    width => 10,
    default => "",
   },
   customInt2 =>
   {
    rules => "integer",
    htmltype => "text",
    width => 10,
    default => "",
   },
   customInt3 =>
   {
    rules => "integer",
    htmltype => "text",
    width => 10,
    default => "",
   },
   customInt4 =>
   {
    rules => "integer",
    htmltype => "text",
    width => 10,
    default => "",
   },
  );

sub custom_fields {
  my $self = shift;

  require DevHelp::Validate;
  DevHelp::Validate->import;
  return DevHelp::Validate::dh_configure_fields
    (
     \%base_custom_validation,
     $self->cfg,
     ARTICLE_CUSTOM_FIELDS_CFG,
     BSE::DB->single->dbh,
    );
}

sub _custom_fields {
  my $self = shift;

  my $fields = $self->custom_fields;
  my %active;
  for my $key (keys %$fields) {
    $fields->{$key}{description}
      and $active{$key} = $fields->{$key};
  }

  return \%active;
}

sub low_edit_tags {
  my ($self, $acts, $request, $article, $articles, $msg, $errors) = @_;

  my $cgi = $request->cgi;
  my $show_full = $cgi->param('f_showfull');
  my $if_error = $msg || ($errors && keys %$errors) || $request->cgi->param("_e");
  #$msg ||= join "\n", map escape_html($_), $cgi->param('message'), $cgi->param('m');
  $msg .= $request->message($errors);
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
  $request->set_article(article => $article);
  $request->set_variable(ifnew => !$article->{id});
  my $cfg = $self->{cfg};
  my $mbcs = $cfg->entry('html', 'mbcs', 0);
  my $tag_hash = $mbcs ? \&tag_hash_mbcs : \&tag_hash;
  my $thumbs_obj_real = $self->_get_thumbs_class();
  my $thumbs_obj = $show_full ? undef : $thumbs_obj_real;
  my @images;
  my $image_index;
  my $current_image;
  my @children;
  my $child_index;
  my %stepkids;
  my @allkids;
  my $allkid_index;
  my @possstepkids;
  my @stepparents;
  my $stepparent_index;
  my @stepparent_targs;
  my @stepparentpossibles;
  my @files;
  my $file_index;
  my @groups;
  my $current_group;
  my $it = BSE::Util::Iterate->new;
  my $ito = BSE::Util::Iterate::Objects->new;
  my $ita = BSE::Util::Iterate::Article->new(req => $request);

  my $custom = $self->_custom_fields;
  # only return the fields that are defined
  $request->set_variable(custom => $custom);
  $request->set_variable(errors => $errors || {});

  return
    (
     $request->admin_tags,
     article => sub { tag_article($article, $cfg, $_[0]) },
     old => [ \&tag_old, $article, $cgi ],
     default => [ \&tag_default, $self, $request, $article ],
     articleType => [ \&tag_art_type, $article->{level}, $cfg ],
     parentType => [ \&tag_art_type, $article->{level}-1, $cfg ],
     ifNew => [ \&tag_if_new, $article ],
     list => [ \&tag_list, $self, $article, $articles, $cgi, $request ],
     script => $ENV{SCRIPT_NAME},
     level => $article->{level},
     checked => \&tag_checked,
     $it->make_iterator
     ([ \&iter_get_images, $self, $article ], 'image', 'images', \@images, 
      \$image_index, undef, \$current_image),
     image => [ tag_image => $self, $cfg, \$current_image ],
     thumbimage => [ \&tag_thumbimage, $cfg, $thumbs_obj, \$current_image ],
     ifThumbs => defined($thumbs_obj),
     ifCanThumbs => defined($thumbs_obj_real),
     imgmove => [ \&tag_imgmove, $request, $article, \$image_index, \@images ],
     message => $msg,
     ifError => $if_error,
     $ita->make
     (
      code => [ \&iter_get_kids, $article, $articles ], 
      single => 'child',
      plural => 'children',
      data => \@children,
      index => \$child_index,
     ),
     ifchildren => \&tag_if_children,
     childtype => [ \&tag_art_type, $article->{level}+1, $cfg ],
     ifHaveChildType => [ \&tag_if_have_child_type, $article->{level}, $cfg ],
     movechild => [ \&tag_movechild, $self, $request, $article, \@children, 
		    \$child_index],
     is => \&tag_is,
     templates => [ \&tag_templates, $self, $article, $cfg, $cgi ],
     titleImages => [ \&tag_title_images, $self, $article, $cfg, $cgi ],
     editParent => [ \&tag_edit_parent, $article ],
     $ita->make
     (
      code => [ \&iter_allkids, $article ],
      single => 'kid',
      plural => 'kids',
      data => \@allkids,
      index => \$allkid_index,
     ),
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
     $ita->make
     (
      code => [ \&iter_get_stepparents, $article ],
      single => 'stepparent',
      plural => 'stepparents',
      data => \@stepparents,
      index => \$stepparent_index,
     ),
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
     $ito->make
     (
      code => [ iter_files => $self, $article ],
      single => 'file',
      plural => 'files',
      data => \@files,
      index => \$file_index,
     ),
     movefiles => 
     [ \&tag_movefiles, $self, $request, $article, \@files, \$file_index ],
     $it->make
     (
      code => [ iter_file_metas => $self, \@files, \$file_index ],
      plural => "file_metas",
      single => "file_meta",
      nocache => 1,
     ),
     ifFileExists => sub {
       @files && $file_index >= 0 && $file_index < @files
	 or return 0;

       return -f ($files[$file_index]->full_filename($cfg));
     },
     file_display => [ tag_file_display => $self, \@files, \$file_index ],
     DevHelp::Tags->make_iterator2
     (\&iter_admin_users, 'iadminuser', 'adminusers'),
     DevHelp::Tags->make_iterator2
     (\&iter_admin_groups, 'iadmingroup', 'admingroups'),
     edit => [ \&tag_edit_link, $cfg, $article ],
     error => [ $tag_hash, $errors ],
     error_img => [ \&tag_error_img, $cfg, $errors ],
     ifFieldPerm => [ \&tag_if_field_perm, $request, $article ],
     parent => [ \&tag_article, $parent, $cfg ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_flags, $self ], 'flag', 'flags' ),
     ifFlagSet => [ \&tag_if_flag_set, $article ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_crumbs, $article, $articles ], 'crumb', 'crumbs' ),
     typename => \&tag_typename,
     $it->make_iterator([ \&iter_groups, $request ], 
			'group', 'groups', \@groups, undef, undef,
			\$current_group),
     $it->make_iterator([ iter_image_stores => $self], 
			'image_store', 'image_stores'),
     $it->make_iterator([ iter_file_stores => $self], 
			'file_store', 'file_stores'),
     ifGroupRequired => [ \&tag_ifGroupRequired, $article, \$current_group ],
     category => [ tag_category => $self, $articles, $article ],
     $ito->make
     (
      single => "tag",
      plural => "tags",
      code => [ iter_tags => $self, $article ],
     ),
    );
}

sub iter_image_stores {
  my ($self) = @_;

  my $mgr = $self->_image_manager;

  return map +{ name => $_->name, description => $_->description },
    $mgr->all_stores;
}

sub _file_manager {
  my ($self) = @_;

  require BSE::TB::ArticleFiles;

  return BSE::TB::ArticleFiles->file_manager($self->cfg);
}

sub iter_file_stores {
  my ($self) = @_;

  require BSE::TB::ArticleFiles;
  my $mgr = $self->_file_manager($self->cfg);

  return map +{ name => $_->name, description => $_->description },
    $mgr->all_stores;
}

sub iter_groups {
  my ($req) = @_;

  require BSE::TB::SiteUserGroups;
  BSE::TB::SiteUserGroups->admin_and_query_groups($req->cfg);
}

sub tag_ifGroupRequired {
  my ($article, $rgroup) = @_;

  $article->{id}
    or return 0;

  $$rgroup or return 0;

  $article->is_accessible_to($$rgroup);
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

  return $request->response($template, \%acts);
}

sub edit_form {
  my ($self, $request, $article, $articles, $msg, $errors) = @_;

  return $self->low_edit_form($request, $article, $articles, $msg, $errors);
}

sub _dummy_article {
  my ($self, $req, $articles, $rmsg) = @_;

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
  unless (@$values) {
    $$rmsg = "You can't add children to any article at that level";
    return;
  }

  return \%article;
}

sub add_form {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  return $self->low_edit_form($req, $article, $articles, $msg, $errors);
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
  if (exists $data->{linkAlias} 
      && length $data->{linkAlias}) {
    unless ($data->{linkAlias} =~ /\A[a-zA-Z0-9-_]+\z/
	    && $data->{linkAlias} =~ /[A-Za-z]/) {
      $errors->{linkAlias} = "Link alias must contain only alphanumerics and contain at least one letter";
    }
  }

  if (defined $data->{category}) {
    unless (first { $_->{id} eq $data->{category} } $self->categories($articles)) {
      $errors->{category} = "msg:bse/admin/edit/category/unknown";
    }
  }

  require DevHelp::Validate;
  DevHelp::Validate->import('dh_validate_hash');
  dh_validate_hash($data, $errors,
		   {
		    fields => $self->_custom_fields,
		    optional => 1,
		    dbh => BSE::DB->single->dbh,
		   },
		   $self->cfg, ARTICLE_CUSTOM_FIELDS_CFG);
}

sub validate {
  my ($self, $data, $articles, $errors) = @_;

  $self->_validate_common($data, $articles, $errors);
  if (!$errors->{linkAlias} && defined $data->{linkAlias} && length $data->{linkAlias}) {
    my $other = $articles->getBy(linkAlias => $data->{linkAlias});
    $other
      and $errors->{linkAlias} =
	"Duplicate link alias - already used by article $other->{id}";
  }
  custom_class($self->{cfg})
    ->article_validate($data, undef, $self->typename, $errors);

  return !keys %$errors;
}

sub validate_old {
  my ($self, $article, $data, $articles, $errors, $ajax) = @_;

  $self->_validate_common($data, $articles, $errors, $article);
  custom_class($self->{cfg})
    ->article_validate($data, $article, $self->typename, $errors);

  if (exists $data->{release}) {
    if ($ajax && !dh_parse_sql_date($data->{release})
	|| !$ajax && !dh_parse_date($data->{release})) {
      $errors->{release} = "Invalid release date";
    }
  }

  if (!$errors->{linkAlias} 
      && defined $data->{linkAlias} 
      && length $data->{linkAlias} 
      && $data->{linkAlias} ne $article->{linkAlias}) {
    my $other = $articles->getBy(linkAlias => $data->{linkAlias});
    $other && $other->{id} != $article->{id}
      and $errors->{linkAlias} = "Duplicate link alias - already used by article $other->{id}";
  }

  return !keys %$errors;
}

sub validate_parent {
  1;
}

sub fill_new_data {
  my ($self, $req, $data, $articles) = @_;

  my $custom = $self->_custom_fields;
  for my $key (keys %$custom) {
    my ($value) = $req->cgi->param($key);
    if (defined $value) {
      if ($key =~ /^customDate/) {
	require DevHelp::Date;
	my $msg;
	if (my ($year, $month, $day) =
	    DevHelp::Date::dh_parse_date($value, \$msg)) {
	  $data->{$key} = sprintf("%04d-%02d-%02d", $year, $month, $day);
	}
	else {
	  $data->{$key} = undef;
	}
      }
      elsif ($key =~ /^customInt/) {
	if ($value =~ /\S/) {
	  $data->{$key} = $value;
	}
	else {
	  $data->{$key} = undef;
	}
      }
      else {
	$data->{$key} = $value;
      }
    }
  }

  custom_class($self->{cfg})
    ->article_fill_new($data, $self->typename);

  1;
}

sub link_path {
  my ($self, $article) = @_;

  # check the config for the article and any of its ancestors
  my $work_article = $article;
  my $path = $self->{cfg}->entry('article uris', $work_article->{id});
  while (!$path) {
    last if $work_article->{parentid} == -1;
    $work_article = $work_article->parent;
    $path = $self->{cfg}->entry('article uris', $work_article->{id});
  }
  return $path if $path;

  $self->default_link_path($article);
}

sub default_link_path {
  my ($self, $article) = @_;

  $self->{cfg}->entry('uri', 'articles', '/a');
}

sub make_link {
  my ($self, $article) = @_;

  $article->is_linked
    or return "";

  my $title = $article->title;
  if ($article->is_dynamic) {
    (my $extra = $title) =~ tr/A-Za-z0-9/-/sc;
    return "/cgi-bin/page.pl?page=$article->{id}&title=".escape_uri($extra);
  }

  my $article_uri = $self->link_path($article);
  my $link = "$article_uri/$article->{id}.html";
  my $link_titles = $self->{cfg}->entryBool('basic', 'link_titles', 0);
  if ($link_titles) {
    (my $extra = $title) =~ tr/A-Za-z0-9/-/sc;
    $link .= "/" . $extra . "_html";
  }

  $link;
}

sub save_columns {
  my ($self, $table_object) = @_;

  my @columns = $table_object->rowClass->columns;
  shift @columns;

  return @columns;
}

sub _validate_tags {
  my ($self, $tags, $errors) = @_;

  my $fail = 0;
  my @errors;
  for my $tag (@$tags) {
    my $error;
    if ($tag =~ /\S/
	&& !BSE::TB::Tags->valid_name($tag, \$error)) {
      push @errors, "msg:bse/admin/edit/tags/invalid/$error";
      $errors->{tags} = \@errors;
      ++$fail;
    }
    else {
      push @errors, undef;
    }
  }

  return $fail;
}

sub save_new {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_add_article")
    or return $self->csrf_error($req, undef, "admin_add_article", "Add Article");
  
  my $cgi = $req->cgi;
  my %data;
  my $table_object = $self->table_object($articles);
  my @columns = $self->save_columns($table_object);
  $self->save_thumbnail($cgi, undef, \%data);
  for my $name (@columns) {
    $data{$name} = $cgi->param($name) 
      if defined $cgi->param($name);
  }
  $data{flags} = join '', sort $cgi->param('flags');

  my $msg;
  my %errors;
  if (!defined $data{parentid} || $data{parentid} eq '') {
    $errors{parentid} = "Please select a parent";
  }
  elsif ($data{parentid} !~ /^(?:-1|\d+)$/) {
    $errors{parentid} = "Invalid parent selection (template bug)";
  }
  $self->validate(\%data, $articles, \%errors);

  my $save_tags = $cgi->param("_save_tags");
  my @tags;
  if ($save_tags) {
    @tags = $cgi->param("tags");
    $self->_validate_tags(\@tags, \%errors);
  }

  if (keys %errors) {
    if ($req->is_ajax) {
      return $req->json_content
	(
	 success => 0,
	 errors => \%errors,
	 error_code => "FIELD",
	 message => $req->message(\%errors),
	);
    }
    else {
      return $self->add_form($req, $article, $articles, $msg, \%errors);
    }
  }

  my $parent;
  my $parent_msg;
  my $parent_code;
  if ($data{parentid} > 0) {
    $parent = $articles->getByPkey($data{parentid}) or die;
    if ($req->user_can('edit_add_child', $parent)) {
      for my $name (@columns) {
	if (exists $data{$name} && 
	    !$req->user_can("edit_add_field_$name", $parent)) {
	  delete $data{$name};
	}
      }
    }
    else {
      $parent_msg = "You cannot add a child to that article";
      $parent_code = "ACCESS";
    }
  }
  else {
    if ($req->user_can('edit_add_child')) {
      for my $name (@columns) {
	if (exists $data{$name} && 
	    !$req->user_can("edit_add_field_$name")) {
	  delete $data{$name};
	}
      }
    }
    else {
      $parent_msg = "You cannot create a top-level article";
      $parent_code = "ACCESS";
    }
  }
  if (!$parent_msg) {
    $self->validate_parent(\%data, $articles, $parent, \$parent_msg)
      or $parent_code = "PARENT";
  }
  if ($parent_msg) {
    if ($req->is_ajax) {
      return $req->json_content
	(
	 success => 0,
	 message => $parent_msg,
	 error_code => $parent_code,
	 errors => {},
	);
    }
    else {
      return $self->add_form($req, $article, $articles, $parent_msg);
    }
  }

  my $level = $parent ? $parent->{level}+1 : 1;
  $data{level} = $level;
  $data{displayOrder} = time;
  $data{link} ||= '';
  $data{admin} ||= '';
  $data{generator} = $self->generator;
  $data{lastModified} = now_sqldatetime();
  $data{listed} = 1 unless defined $data{listed};

# Added by adrian
  $data{pageTitle} = '' unless defined $data{pageTitle};
  my $user = $req->getuser;
  $data{createdBy} = $user ? $user->{logon} : '';
  $data{lastModifiedBy} = $user ? $user->{logon} : '';
  $data{created} =  now_sqldatetime();
# end adrian

  $data{force_dynamic} = 0;
  $data{cached_dynamic} = 0;
  $data{inherit_siteuser_rights} = 1;

# Added by adrian
  $data{metaDescription} = '' unless defined $data{metaDescription};
  $data{metaKeywords} = '' unless defined $data{metaKeywords};
# end adrian

  $self->fill_new_data($req, \%data, $articles);
  for my $col (qw(titleImage imagePos template keyword menu titleAlias linkAlias body author summary category)) {
    defined $data{$col} 
      or $data{$col} = $self->default_value($req, \%data, $col);
  }

  for my $col (qw/force_dynamic inherit_siteuser_rights/) {
    if ($req->user_can("edit_add_field_$col", $parent)
	&& $cgi->param("save_$col")) {
      $data{$col} = $cgi->param($col) ? 1 : 0;
    }
    else {
      $data{$col} = $self->default_value($req, \%data, $col);
    }
  }

  unless ($req->is_ajax) {
    for my $col (qw(release expire)) {
      $data{$col} = sql_date($data{$col});
    }
  }

  # these columns are handled a little differently
  for my $col (qw(release expire threshold summaryLength )) {
    $data{$col} 
      or $data{$col} = $self->default_value($req, \%data, $col);
  }

  my @cols = $table_object->rowClass->columns;
  shift @cols;

  # fill out anything else from defaults
  for my $col (@columns) {
    exists $data{$col}
      or $data{$col} = $self->default_value($req, \%data, $col);
  }

  $article = $table_object->add(@data{@cols});

  $self->save_new_more($req, $article, \%data);

  # we now have an id - generate the links

  $article->update_dynamic($self->{cfg});
  my $cgi_uri = $self->{cfg}->entry('uri', 'cgi', '/cgi-bin');
  $article->setAdmin("$cgi_uri/admin/admin.pl?id=$article->{id}");
  $article->setLink($self->make_link($article));
  $article->save();

  my ($after_id) = $cgi->param("_after");
  if (defined $after_id) {
    Articles->reorder_child($article->{parentid}, $article->{id}, $after_id);
    # reload, the displayOrder probably changed
    $article = $articles->getByPkey($article->{id});
  }

  if ($save_tags) {
    my $error;
    $article->set_tags([ grep /\S/, @tags ], \$error);
  }

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  if ($req->is_ajax) {
    return $req->json_content
      (
       {
	success => 1,
	article => $self->_article_data($req, $article),
       },
      );
  }

  my $r = $cgi->param('r');
  if ($r) {
    $r .= ($r =~ /\?/) ? '&' : '?';
    $r .= "id=$article->{id}";
  }
  else {
    $r = admin_base_url($req->cfg) . $article->{admin};
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
  my $custom = $self->_custom_fields;
  for my $key (keys %$custom) {
    if (exists $data->{$key}) {
      if ($key =~ /^customDate/) {
	require DevHelp::Date;
	my $msg;
	if (my ($year, $month, $day) =
	    DevHelp::Date::dh_parse_date($data->{$key}, \$msg)) {
	  $article->set($key, sprintf("%04d-%02d-%02d", $year, $month, $day));
	}
	else {
	  $article->set($key => undef);
	}
      }
      elsif ($key =~ /^customInt/) {
	if ($data->{$key} =~ /\S/) {
	  $article->set($key => $data->{$key});
	}
	else {
	  $article->set($key => undef);
	}
      }
      else {
	$article->set($key => $data->{$key});
      }
    }
  }
  custom_class($self->{cfg})
    ->article_fill_old($article, $data, $self->typename);

  return 1;
}

sub _article_data {
  my ($self, $req, $article) = @_;

  my $article_data = $article->data_only;
  $article_data->{link} = $article->link($req->cfg);
  $article_data->{images} =
    [
     map $self->_image_data($req->cfg, $_), $article->images
    ];
  $article_data->{files} =
    [
     map $_->data_only, $article->files,
    ];
  $article_data->{tags} =
    [
     $article->tags, # just the names
    ];

  return $article_data;
}

sub save_more {
  my ($self, $req, $article, $data) = @_;
  # nothing to do here
}

sub save_new_more {
  my ($self, $req, $article, $data) = @_;
  # nothing to do here
}

=item save

Error codes:

=over

=item *

ACCESS - user doesn't have access to this article.

=item *

LASTMOD - lastModified value doesn't match that in the article

=item *

PARENT - invalid parentid specified

=back

=cut

sub save {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_article")
    or return $self->csrf_error($req, $article, "admin_save_article", "Save Article");

  $req->user_can(edit_save => $article)
    or return $self->_service_error
      ($req, $article, $articles, "You don't have access to save this article",
       {}, "ACCESS");

  my $old_dynamic = $article->is_dynamic;
  my $cgi = $req->cgi;
  my %data;
  my $table_object = $self->table_object($articles);
  my @save_cols = $self->save_columns($table_object);
  for my $name (@save_cols) {
    $data{$name} = $cgi->param($name) 
      if defined($cgi->param($name)) and $name ne 'id' && $name ne 'parentid'
	&& $req->user_can("edit_field_edit_$name", $article);
  }
  
# Added by adrian
# checks editor lastModified against record lastModified
  if ($self->{cfg}->entry('editor', 'check_modified')) {
    if ($article->{lastModified} ne $cgi->param('lastModified')) {
      my $whoModified = '';
      my $timeModified = ampm_time($article->{lastModified});
      if ($article->{lastModifiedBy}) {
        $whoModified = "by '$article->{lastModifiedBy}'";
      }
      print STDERR "non-matching lastModified, article not saved\n";
      my $msg = "Article changes not saved, this article was modified $whoModified at $timeModified since this editor was loaded";
      return $self->_service_error($req, $article, $articles, $msg, {}, "LASTMOD");
    }
  }
# end adrian
  
  # possibly this needs tighter error checking
  $data{flags} = join '', sort $cgi->param('flags')
    if $req->user_can("edit_field_edit_flags", $article);
  my %errors;
  if (exists $article->{template} &&
      $article->{template} =~ m|\.\.|) {
    $errors{template} = "Please only select templates from the list provided";
  }

  my $save_tags = $cgi->param("_save_tags");
  my @tags;
  if ($save_tags) {
    @tags = $cgi->param("tags");
    $self->_validate_tags(\@tags, \%errors);
  }
  $self->validate_old($article, \%data, $articles, \%errors, scalar $req->is_ajax)
    or return $self->_service_error($req, $article, $articles, undef, \%errors, "FIELD");
  $self->save_thumbnail($cgi, $article, \%data)
    if $req->user_can('edit_field_edit_thumbImage', $article);
  if (exists $data{flags} && $data{flags} =~ /D/) {
    $article->remove_html;
  }
  $self->fill_old_data($req, $article, \%data);
  
  # reparenting
  my $newparentid = $cgi->param('parentid');
  if ($newparentid
      && $req->user_can('edit_field_edit_parentid', $article)
      && $newparentid != $article->{parentid}) {
    my $newparent;
    my $parent_editor;
    if ($newparentid == -1) {
      require BSE::Edit::Site;
      $newparent = BSE::TB::Site->new;
      $parent_editor = BSE::Edit::Site->new(cfg => $req->cfg);
    }
    else {
      $newparent = $articles->getByPkey($newparentid);
      ($parent_editor, $newparent) = $self->article_class($newparent, $articles, $req->cfg);
    }
    if ($newparent) {
      my $msg;
      if ($self->can_reparent_to($article, $newparent, $parent_editor, $articles, \$msg)
	 && $self->reparent($article, $newparentid, $articles, \$msg)) {
	# nothing to do here
      }
      else {
	return $self->_service_error($req, $article, $articles, $msg, {}, "PARENT");
      }
    }
    else {
      return $self->_service_error($req, $article, $articles, "No such parent article", {}, "PARENT");
    }
  }

  $article->{listed} = $cgi->param('listed')
   if defined $cgi->param('listed') && 
      $req->user_can('edit_field_edit_listed', $article);

  if ($req->user_can('edit_field_edit_release', $article)) {
    my $release = $cgi->param("release");
    if (defined $release && $release =~ /\S/) {
      if ($req->is_ajax) {
	$article->{release} = $release;
      }
      else {
	$article->{release} = sql_date($release)
      }
    }
  }

  $article->{expire} = sql_date($cgi->param('expire')) || $Constants::D_99
    if defined $cgi->param('expire') && 
      $req->user_can('edit_field_edit_expire', $article);
  for my $col (qw/force_dynamic inherit_siteuser_rights/) {
    if ($req->user_can("edit_field_edit_$col", $article)
	&& $cgi->param("save_$col")) {
      $article->{$col} = $cgi->param($col) ? 1 : 0;
    }
  }

  $article->mark_modified(actor => $req->getuser || "U");

  my @save_group_ids = $cgi->param('save_group_id');
  if ($req->user_can('edit_field_edit_group_id')
      && @save_group_ids) {
    require BSE::TB::SiteUserGroups;
    my %groups = map { $_->{id} => $_ }
      BSE::TB::SiteUserGroups->admin_and_query_groups($self->{cfg});
    my %set = map { $_ => 1 } $cgi->param('group_id');
    my %current = map { $_ => 1 } $article->group_ids;

    for my $group_id (@save_group_ids) {
      $groups{$group_id} or next;
      if ($current{$group_id} && !$set{$group_id}) {
	$article->remove_group_id($group_id);
      }
      elsif (!$current{$group_id} && $set{$group_id}) {
	$article->add_group_id($group_id);
      }
    }
  }

  my $old_link = $article->{link};
  # this need to go last
  $article->update_dynamic($self->{cfg});
  if (!$self->{cfg}->entry('protect link', $article->{id})) {
    my $article_uri = $self->make_link($article);
    $article->setLink($article_uri);
  }

  $article->save();

  if ($save_tags) {
    my $error;
    $article->set_tags([ grep /\S/, @tags ], \$error);
  }

  # fix the kids too
  my @extra_regen;
  @extra_regen = $self->update_child_dynamic($article, $articles, $req);
  
  if ($article->is_dynamic || $old_dynamic) {
    if (!$old_dynamic and $old_link) {
      unlink $article->link_to_filename($self->{cfg}, $old_link);
    }
    elsif (!$article->is_dynamic) {
      unlink $article->cached_filename($self->{cfg});
    }
  }

  my ($after_id) = $cgi->param("_after");
  if (defined $after_id) {
    Articles->reorder_child($article->{parentid}, $article->{id}, $after_id);
    # reload, the displayOrder probably changed
    $article = $articles->getByPkey($article->{id});
  }

  if ($Constants::AUTO_GENERATE) {
    generate_article($articles, $article);
    for my $regen_id (@extra_regen) {
      my $regen = $articles->getByPkey($regen_id);
      BSE::Regen::generate_low($articles, $regen, $self->{cfg});
    }
  }

  $self->save_more($req, $article, \%data);

  if ($req->is_ajax) {
    return $req->json_content
      (
       {
	success => 1,
	article => $self->_article_data($req, $article),
       },
      );
  }

  return $self->refresh($article, $cgi, undef, 'Article saved');
}

sub can_reparent_to {
  my ($self, $article, $newparent, $parent_editor, $articles, $rmsg) = @_;

  my @child_types = $parent_editor->child_types;
  if (!grep $_ eq ref $self, @child_types) {
    my ($child_type) = (ref $self) =~ /(\w+)$/;
    my ($parent_type) = (ref $parent_editor) =~ /(\w+)$/;
    
    $$rmsg = "A $child_type cannot be a child of a $parent_type";
    return;
  }
  
  # the article cannot become a child of itself or one of it's 
  # children
  if ($article->{id} == $newparent->id
      || $self->is_descendant($article->id, $newparent->id, $articles)) {
    $$rmsg = "Cannot become a child of itself or of a descendant";
    return;
  }

  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  if ($self->shop_article) { # if this article belongs in the shop
    unless ($newparent->id == $shopid
	    || $self->is_descendant($shopid, $newparent->{id}, $articles)) {
      $$rmsg = "This article belongs in the shop";
      return;
    }
  }
  else {
    if ($newparent->id == $shopid
	|| $self->is_descendant($shopid, $newparent->id, $articles)) {
      $$rmsg = "This article doesn't belong in the shop";
      return;
    }
  }

  return 1;
}

sub shop_article { 0 }

sub update_child_dynamic {
  my ($self, $article, $articles, $req) = @_;

  my $cfg = $req->cfg;
  my @stack = $article->children;
  my @regen;
  while (@stack) {
    my $workart = pop @stack;
    my $old_dynamic = $workart->is_dynamic; # before update
    my $old_link = $workart->{link};
    my $editor;
    ($editor, $workart) = $self->article_class($workart, $articles, $cfg);

    $workart->update_dynamic($cfg);
    if ($old_dynamic != $workart->is_dynamic) {
      # update the link
      if ($article->{link} && !$cfg->entry('protect link', $workart->{id})) {
	my $uri = $editor->make_link($workart);
	$workart->setLink($uri);

	!$old_dynamic && $old_link
	  and unlink $workart->link_to_filename($cfg, $old_link);
	$workart->is_dynamic
	  or unlink $workart->cached_filename($cfg);
      }

      # save dynamic cache change and link if that changed
      $workart->save;
    }
    push @stack, $workart->children;
    push @regen, $workart->{id};
  }

  @regen;
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

# Added by adrian
# Converts 24hr time to 12hr AM/PM time
sub ampm_time {
  my $str = shift;
  my ($hour, $minute, $second, $ampm);

  # look for a time
  if (($hour, $minute, $second) = ($str =~ m!(\d+):(\d+):(\d+)!)) {
    if ($hour > 12) {
      $hour -= 12;
      $ampm = 'PM';
    }
    else {
      $hour = 12 if $hour == 0;
      $ampm = 'AM';
    }
    return sprintf("%02d:%02d:%02d $ampm", $hour, $minute, $second);
  }
  return undef;
}
# end adrian

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
  my $imagedir = cfg_image_dir($self->{cfg});
  if ($cgi->param('remove_thumb') && $original && $original->{thumbImage}) {
    unlink("$imagedir/$original->{thumbImage}");
    @$newdata{qw/thumbImage thumbWidth thumbHeight/} = ('', 0, 0);
  }
  my $image_name = $cgi->param('thumbnail');
  my $image = $cgi->upload('thumbnail');
  if ($image_name && -s $image) {
    # where to put it...
    my $name = '';
    $image_name =~ /([\w.-]+)$/ and $name = $1;
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

=item add_stepkid

Add a step child to an article.

Parameters:

=over

=item *

id - parent article id (required)

=item *

stepkid - child article id (required)

=item *

_after - id of the allkid of id to position the stepkid after
(optional)

=back

Returns a FIELD error for an invalid stepkid.

Returns an ACCESS error for insufficient access.

Return an ADD error for a general add failure.

On success returns:

  {
   success: 1,
   relationship: { childId: I<childid>, parentId: I<parentid> }
  }

=back

=cut

sub add_stepkid {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_add_stepkid")
    or return $self->csrf_error($req, $article, "admin_add_stepkid", "Add Stepkid");

  $req->user_can(edit_stepkid_add => $article)
    or return $self->_service_error($req, $article, $articles,
			       "You don't have access to add step children to this article", {}, "ACCESS");

  my $cgi = $req->cgi;
  require BSE::Admin::StepParents;

  my %errors;
  my $childId = $cgi->param('stepkid');
  defined $childId
    or $errors{stepkid} = "No stepkid supplied to add_stepkid";
  unless ($errors{stepkid}) {
    $childId =~ /^\d+$/
      or $errors{stepkid} = "Invalid stepkid supplied to add_stepkid";
  }
  my $child;
  unless ($errors{stepkid}) {
    $child = $articles->getByPkey($childId)
      or $errors{stepkid} = "Article $childId not found";
  }
  keys %errors
    and return $self->_service_error
      ($req, $article, $articles, $errors{stepkid}, \%errors, "FIELD");

  $req->user_can(edit_stepparent_add => $child)
    or return $self->_service_error($req, $article, $articles, "You don't have access to add a stepparent to that article", {}, "ACCESS");

  my $new_entry;
  eval {
    
    my $release = $cgi->param('release');
    dh_parse_date($release) or $release = undef;
    my $expire = $cgi->param('expire');
    dh_parse_date($expire) or $expire = undef;
  
    $new_entry = 
      BSE::Admin::StepParents->add($article, $child, $release, $expire);
  };
  if ($@) {
    return $self->_service_error($req, $article, $articles, $@, {}, "ADD");
  }

  my $after_id = $cgi->param("_after");
  if (defined $after_id) {
    Articles->reorder_child($article->id, $child->id, $after_id);
  }

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       relationship => $new_entry->data_only,
      );
  }
  else {
    $self->refresh($article, $cgi, 'step', 'Stepchild added');
  }
}

=item del_stepkid

Remove a stepkid relationship.

Parameters:

=over

=item *

id - parent article id (required)

=item *

stepkid - child article id (required)

=back

Returns a FIELD error for an invalid stepkid.

Returns an ACCESS error for insufficient access.

Return a DELETE error for a general delete failure.

=cut

sub del_stepkid {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_remove_stepkid")
    or return $self->csrf_error($req, $article, "admin_del_stepkid", "Delete Stepkid");
  $req->user_can(edit_stepkid_delete => $article)
    or return $self->_service_error($req, $article, $articles,
			       "You don't have access to delete stepchildren from this article", {}, "ACCESS");

  my $cgi = $req->cgi;

  my %errors;
  my $childId = $cgi->param('stepkid');
  defined $childId
    or $errors{stepkid} = "No stepkid supplied to add_stepkid";
  unless ($errors{stepkid}) {
    $childId =~ /^\d+$/
      or $errors{stepkid} = "Invalid stepkid supplied to add_stepkid";
  }
  my $child;
  unless ($errors{stepkid}) {
    $child = $articles->getByPkey($childId)
      or $errors{stepkid} = "Article $childId not found";
  }
  keys %errors
    and return $self->_service_error
      ($req, $article, $articles, $errors{stepkid}, \%errors, "FIELD");

  $req->user_can(edit_stepparent_delete => $child)
    or return _service_error($req, $article, $article, "You cannot remove stepparents from that article", {}, "ACCESS");
    

  require BSE::Admin::StepParents;
  eval {
    BSE::Admin::StepParents->del($article, $child);
  };
  
  if ($@) {
    return $self->_service_error($req, $article, $articles, $@, {}, "DELETE");
  }
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  if ($req->is_ajax) {
    return $req->json_content(success => 1);
  }
  else {
    return $self->refresh($article, $cgi, 'step', 'Stepchild deleted');
  }
}

sub save_stepkids {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_stepkids")
    or return $self->csrf_error($req, $article, "admin_save_stepkids", "Save Stepkids");

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
	elsif (dh_parse_date($date)) {
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
  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'step', 'Stepchild information saved');
}

=item a_restepkid

Moves a stepkid from one parent to another, and sets the order within
that new stepparent.

Parameters:

=over

=item *

id - id of the step kid to move (required)

=item *

parentid - id of the parent in the stepkid relationship (required)

=item *

newparentid - the new parent for the stepkid relationship (optional)

=item *

_after - id of the allkid under newparentid (or parentid if
newparentid isn't supplied) to place the stepkid after (0 to place at
the start)

=back

Errors:

=over

=item *

NOPARENTID - parentid parameter not supplied

=item *

BADPARENTID - non-numeric parentid supplied

=item *

NOTFOUND - no stepkid relationship from parentid was found

=item *

BADNEWPARENT - newparentid is non-numeric

=item *

UNKNOWNNEWPARENT - no article id newparentid found

=item *

NEWPARENTDUP - there's already a stepkid relationship between
newparentid and id.

=back

=cut

sub req_restepkid {
  my ($self, $req, $article, $articles) = @_;

  # first, identify the stepkid link
  my $cgi = $req->cgi;
  require OtherParents;
  my $parentid = $cgi->param("parentid");
  defined $parentid
    or return $self->_service_error($req, $article, $articles, "Missing parentid", {}, "NOPARENTID");
  $parentid =~ /^\d+$/
    or return $self->_service_error($req, $article, $articles, "Invalid parentid", {}, "BADPARENTID");

  my ($step) = OtherParents->getBy(parentId => $parentid, childId => $article->id)
    or return $self->_service_error($req, $article, $articles, "Unknown relationship", {}, "NOTFOUND");

  my $newparentid = $cgi->param("newparentid");
  if ($newparentid) {
    $newparentid =~ /^\d+$/
      or return $self->_service_error($req, $article, $articles, "Bad new parent id", {}, "BADNEWPARENT");
    my $new_parent = Articles->getByPkey($newparentid)
      or return $self->_service_error($req, $article, $articles, "Unknown new parent id", {}, "UNKNOWNNEWPARENT");
    my $existing = 
      OtherParents->getBy(parentId=>$newparentid, childId=>$article->id)
	and return $self->_service_error($req, $article, $articles, "New parent is duplicate", {}, "NEWPARENTDUP");

    $step->{parentId} = $newparentid;
    $step->save;
  }

  my $after_id = $cgi->param("_after");
  if (defined $after_id) {
    Articles->reorder_child($step->{parentId}, $article->id, $after_id);
  }

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       relationshop => $step->data_only,
      );
  }
  else {
    return $self->refresh($article, $cgi, 'step', "Stepchild moved");
  }
}

sub add_stepparent {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_add_stepparent")
    or return $self->csrf_error($req, $article, "admin_add_stepparent", "Add Stepparent");

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
    $release eq '' or dh_parse_date($release)
      or die "Invalid release date";
    my $expire = $cgi->param('expire');
    defined $expire
      or $expire = '31/12/2999';
    $expire eq '' or dh_parse_date($expire)
      or die "Invalid expire data";
  
    my $newentry = 
      BSE::Admin::StepParents->add($step_parent, $article, $release, $expire);
  };
  $@ and return $self->refresh($article, $cgi, 'step', $@);

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'stepparents', 'Stepparent added');
}

sub del_stepparent {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_remove_stepparent")
    or return $self->csrf_error($req, $article, "admin_del_stepparent", "Delete Stepparent");

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

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'stepparents', 'Stepparent deleted');
}

sub save_stepparents {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_stepparents")
    or return $self->csrf_error($req, $article, "admin_save_stepparents", "Save Stepparents");
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
	elsif (dh_parse_date($date)) {
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

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $cgi, 'stepparents', 
			'Stepparent information saved');
}

sub refresh_url {
  my ($self, $article, $cgi, $name, $message, $extras) = @_;

  my $url = $cgi->param('r');
  if ($url) {
    if ($url !~ /[?&](m|message)=/ && $message) {
      # add in messages if none in the provided refresh
      my @msgs = ref $message ? @$message : $message;
      my $sep = $url =~ /\?/ ? "&" : "?";
      for my $msg (@msgs) {
	$url .= $sep . "m=" . CGI::escape($msg);
      }
    }
  }
  else {
    my $urlbase = admin_base_url($self->{cfg});
    $url = "$urlbase$ENV{SCRIPT_NAME}?id=$article->{id}";
    if ($message) {
      my @msgs = ref $message ? @$message : $message;
      for my $msg (@msgs) {
	$url .= "&m=" . CGI::escape($msg);
      }
    }
    if ($cgi->param('_t')) {
      $url .= "&_t=".CGI::escape($cgi->param('_t'));
    }
    $url .= $extras if defined $extras;
    my $cgiextras = $cgi->param('e');
    $url .= "#$name" if $name;
  }

  return $url;
}

sub refresh {
  my ($self, $article, $cgi, $name, $message, $extras) = @_;

  my $url = $self->refresh_url($article, $cgi, $name, $message, $extras);

  return BSE::Template->get_refresh($url, $self->{cfg});
}

sub show_images {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  my %acts;
  %acts = $self->low_edit_tags(\%acts, $req, $article, $articles, $msg, $errors);
  my $template = 'admin/article_img';

  return $req->dyn_response($template, \%acts);
}

sub save_image_changes {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_images")
    or return $self->csrf_error($req, $article, "admin_save_images", "Save Images");

  $req->user_can(edit_images_save => $article)
    or return $self->edit_form($req, $article, $articles,
				 "You don't have access to save image information for this article");

  my $image_dir = cfg_image_dir($req->cfg);

  my $cgi = $req->cgi;
  my $image_pos = $cgi->param('imagePos');
  if ($image_pos 
      && $image_pos =~ /^(?:tl|tr|bl|br|xx)$/
      && $image_pos ne $article->{imagePos}) {
    $article->{imagePos} = $image_pos;
    $article->save;
  }
  my @images = $self->get_images($article);
  
  @images or
    return $self->refresh($article, $cgi, undef, 'No images to save information for');

  my %changes;
  my %errors;
  my %names;
  my %old_images;
  my @new_images;
  for my $image (@images) {
    my $id = $image->{id};

    my $alt = $cgi->param("alt$id");
    if ($alt ne $image->{alt}) {
      $changes{$id}{alt} = $alt;
    }

    my $url = $cgi->param("url$id");
    if (defined $url && $url ne $image->{url}) {
      $changes{$id}{url} = $url;
    }

    my $name = $cgi->param("name$id");
    if (defined $name && $name ne $image->{name}) {
      if ($name eq '') {
	$changes{$id}{name} = '';
      }
      elsif ($name =~ /^[a-z_]\w*$/i) {
	my $msg;
	if ($self->validate_image_name($name, \$msg)) {
	  # check for duplicates after the loop
	  push @{$names{lc $name}}, $image->{id}
	    if length $name;
	  $changes{$id}{name} = $name;
	}
	else {
	  $errors{"name$id"} = $msg;
	}
      }
      else {
	$errors{"name$id"} = 'Image name must be empty or alphanumeric and unique to the article';
      }
    }
    else {
      push @{$names{lc $image->{name}}}, $image->{id}
	if length $image->{name};
    }

    my $filename = $cgi->param("image$id");
    if (defined $filename && length $filename) {
      my $in_fh = $cgi->upload("image$id");
      if ($in_fh) {
	my $basename;
	my $image_error;
	my ($width, $height, $type) = $self->_validate_image
	  ($filename, $in_fh, \$basename, \$image_error);

	unless ($type) {
	  $errors{"image$id"} = $image_error;
	}

	unless ($errors{"image$id"}) {
	  # work out where to put it
	  require DevHelp::FileUpload;
	  my $msg;
	  my ($image_name, $out_fh) = DevHelp::FileUpload->make_img_filename
	    ($image_dir, $basename, \$msg);
	  if ($image_name) {
	    local $/ = \8192;
	    my $data;
	    while ($data = <$in_fh>) {
	      print $out_fh $data;
	    }
	    close $out_fh;
	    
	    my $full_filename = "$image_dir/$image_name";
	    if ($width) {
	      $old_images{$id} = 
		{ 
		 image => $image->{image}, 
		 storage => $image->{storage}
		};
	      push @new_images, $image_name;
	      
	      $changes{$id}{image} = $image_name;
	      $changes{$id}{storage} = 'local';
	      $changes{$id}{src} = cfg_image_uri() . "/" . $image_name;
	      $changes{$id}{width} = $width;
	      $changes{$id}{height} = $height;
	      $changes{$id}{ftype} = $self->_image_ftype($type);
	    }
	  }
	  else {
	    $errors{"image$id"} = $msg;
	  }
	}
      }
      else {
	# problem uploading
	$errors{"image$id"} = "No image file received";
      }
    }
  }
  # look for duplicate names
  for my $name (keys %names) {
    if (@{$names{$name}} > 1) {
      for my $id (@{$names{$name}}) {
	$errors{"name$id"} = 'Image name must be unique to the article';
      }
    }
  }
  if (keys %errors) {
    # remove files that won't be stored because validation failed
    unlink map "$image_dir/$_", @new_images;

    return $self->edit_form($req, $article, $articles, undef,
			    \%errors);
  }

  my $mgr = $self->_image_manager($req->cfg);
  $req->flash('Image information saved');
  my $changes_found = 0;
  my $auto_store = $cgi->param('auto_storage');
  for my $image (@images) {
    my $id = $image->{id};

    if ($changes{$id}) {
      my $changes = $changes{$id};
      ++$changes_found;
      
      for my $field (keys %$changes) {
	$image->{$field} = $changes->{$field};
      }
      $image->save;
    }

    my $old_storage = $image->{storage};
    my $new_storage = $auto_store ? '' : $cgi->param("storage$id");
    defined $new_storage or $new_storage = $image->{storage};
    $new_storage = $mgr->select_store($image->{image}, $new_storage, $image);
    if ($new_storage ne $old_storage) {
      eval {
	$image->{src} = $mgr->store($image->{image}, $new_storage, $image);
	$image->{storage} = $new_storage;
	$image->save;
      };
      
      if ($old_storage ne 'local') {
	$mgr->unstore($image->{image}, $old_storage);
      }
    }
  }

  # delete any image files that were replaced
  for my $old_image (values %old_images) {
    my ($image, $storage) = @$old_image{qw/image storage/};
    if ($storage ne 'local') {
      $mgr->unstore($image->{image}, $storage);
    }
    unlink "$image_dir/$image";
  }
  
  if ($changes_found) {
    generate_article($articles, $article) if $Constants::AUTO_GENERATE;
  }
    
  return $self->refresh($article, $cgi);
}

=item _service_error

This function is called on various errors.

If a _service parameter was supplied, returns text like:

=over

Result: failure

Field-Error: I<field-name1> - I<message1>

Field-Error: I<field-name2> - I<message2>

=back

If the request is detected as an ajax request or a _ parameter is
supplied, return JSON like:

  { error: I<message> }

Otherwise display the normal edit page with the error.

=cut

sub _service_error {
  my ($self, $req, $article, $articles, $msg, $error, $code, $method) = @_;

  unless ($article) {
    my $mymsg;
    $article = $self->_dummy_article($req, $articles, \$mymsg);
    $article ||=
      {
       map $_ => '', Article->columns
      };
  }

  if ($req->cgi->param('_service')) {
    my $body = '';
    $body .= "Result: failure\n";
    if (ref $error) {
      for my $field (keys %$error) {
	my $text = $error->{$field};
	$text =~ tr/\n/ /;
	$body .= "Field-Error: $field - $text\n";
      }
      my $text = join ('/', values %$error);
      $text =~ tr/\n/ /;
      $body .= "Error: $text\n";
    }
    elsif ($msg) {
      $body .= "Error: $msg\n";
    }
    else {
      $body .= "Error: $error\n";
    }
    return
      {
       type => 'text/plain',
       content => $body,
      };
  }
  elsif ((() = $req->cgi->param('_')) ||
	 (exists $ENV{HTTP_X_REQUESTED_WITH}
	  && $ENV{HTTP_X_REQUESTED_WITH} =~ /XMLHttpRequest/)) {
    $error ||= {};
    my $result = 
      {
       errors => $error,
       success => 0,
      };
    $msg and $result->{message} = $msg;
    $code and $result->{error_code} = $code;
    my $json_result = $req->json_content($result);

    if (!exists $ENV{HTTP_X_REQUESTED_WITH}
	|| $ENV{HTTP_X_REQUESTED_WITH} !~ /XMLHttpRequest/) {
      $json_result->{type} = "text/plain";
    }

    return $json_result;
  }
  else {
    $method ||= "edit_form";
    return $self->$method($req, $article, $articles, $msg, $error);
  }
}

sub _service_success {
  my ($self, $results) = @_;

  my $body = "Result: success\n";
  for my $field (keys %$results) {
    $body .= "$field: $results->{$field}\n";
  }
  return
    {
     type => 'text/plain',
     content => $body,
    };
}

# FIXME: eliminate this method and call get_ftype directly
sub _image_ftype {
  my ($self, $type) = @_;

  require BSE::TB::Images;
  return BSE::TB::Images->get_ftype($type);
}

my %valid_exts =
  (
   tiff => "tiff,tif",
   jpg => "jpeg,jpg",
   pnm => "pbm,pgm,ppm",
  );

sub _validate_image {
  my ($self, $filename, $fh, $rbasename, $error) = @_;

  if ($fh) {
    if (-z $fh) {
      $$error = 'Image file is empty';
      return;
    }
  }
  else {
    $$error = 'Please enter an image filename';
    return;
  }
  my $imagename = $filename;
  $imagename .= ''; # force it into a string
  my $basename = '';
  $imagename =~ tr/ //d;
  $imagename =~ /([\w.-]+)$/ and $basename = $1;

  # for OSs with special text line endings
  use Image::Size;

  my($width,$height, $type) = imgsize($fh);

  unless (defined $width) {
    $$error = "Unknown image file type";
    return;
  }

  my $lctype = lc $type;
  my @valid_exts = split /,/, 
    BSE::Cfg->single->entry("valid image extensions", $lctype,
		$valid_exts{$lctype} || $lctype);

  my ($ext) = $basename =~ /\.(\w+)\z/;
  if (!$ext || !grep $_ eq lc $ext, @valid_exts) {
    $basename .= ".$valid_exts[0]";
  }
  $$rbasename = $basename;

  return ($width, $height, $type);
}

my $last_display_order = 0;

sub do_add_image {
  my ($self, $cfg, $article, $image, %opts) = @_;

  my $errors = $opts{errors}
    or die "No errors parameter";

  my $imageref = $opts{name};
  if (defined $imageref && $imageref ne '') {
    if ($imageref =~ /^[a-z_]\w+$/i) {
      # make sure it's unique
      my @images = $self->get_images($article);
      for my $img (@images) {
	if (defined $img->{name} && lc $img->{name} eq lc $imageref) {
	  $errors->{name} = 'Image name must be unique to the article';
	  last;
	}
      }
    }
    else {
      $errors->{name} = 'Image name must be empty or alphanumeric beginning with an alpha character';
    }
  }
  else {
    $imageref = '';
  }
  unless ($errors->{name}) {
    my $workmsg;
    $self->validate_image_name($imageref, \$workmsg)
      or $errors->{name} = $workmsg;
  }

  my $image_error;
  my $basename;
  my ($width, $height, $type) = 
    $self->_validate_image($opts{filename} || $image, $image, \$basename,
			   \$image_error);
  unless ($width) {
    $errors->{image} = $image_error;
  }

  keys %$errors
    and return;

  # for the sysopen() constants
  use Fcntl;

  my $imagedir = cfg_image_dir($cfg);

  require DevHelp::FileUpload;
  my $msg;
  my ($filename, $fh) =
    DevHelp::FileUpload->make_img_filename($imagedir, $basename, \$msg);
  unless ($filename) {
    $errors->{image} = $msg;
    return;
  }

  my $buffer;

  binmode $fh;

  no strict 'refs';

  # read the image in from the browser and output it to our output filehandle
  print $fh $buffer while read $image, $buffer, 1024;

  # close and flush
  close $fh
    or die "Could not close image file $filename: $!";

  my $display_order = time;
  if ($display_order <= $last_display_order) {
    $display_order = $last_display_order + 1;
  }
  $last_display_order = $display_order;

  my $alt = $opts{alt};
  defined $alt or $alt = '';
  my $url = $opts{url};
  defined $url or $url = '';
  my %image =
    (
     articleId => $article->{id},
     image => $filename,
     alt=>$alt,
     width=>$width,
     height => $height,
     url => $url,
     displayOrder => $display_order,
     name => $imageref,
     storage => 'local',
     src => cfg_image_uri() . '/' . $filename,
     ftype => $self->_image_ftype($type),
    );
  require BSE::TB::Images;
  my @cols = BSE::TB::Image->columns;
  shift @cols;
  my $imageobj = BSE::TB::Images->add(@image{@cols});

  my $storage = $opts{storage};
  defined $storage or $storage = 'local';
  my $image_manager = $self->_image_manager($cfg);
  local $SIG{__DIE__};
  eval {
    my $src;
    $storage = $image_manager->select_store($filename, $storage, $imageobj);
    $src = $image_manager->store($filename, $storage, $imageobj);
      
    if ($src) {
      $imageobj->{src} = $src;
      $imageobj->{storage} = $storage;
      $imageobj->save;
    }
  };
  if ($@) {
    $errors->{flash} = $@;
  }

  return $imageobj;
}

sub _image_data {
  my ($self, $cfg, $image) = @_;

  my $data = $image->data_only;
  $data->{src} = $image->image_url($cfg);

  return $data;
}

sub add_image {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_add_image")
    or return $self->csrf_error($req, $article, "admin_add_image", "Add Image");
  $req->user_can(edit_images_add => $article)
    or return $self->_service_error($req, $article, $articles,
				    "You don't have access to add new images to this article");

  my $cgi = $req->cgi;

  my %errors;

  my $save_tags = $cgi->param("_save_tags");
  my @tags;
  if ($save_tags) {
    @tags = $cgi->param("tags");
    $self->_validate_tags(\@tags, \%errors);
  }

  my $imageobj =
    $self->do_add_image
      (
       $req->cfg,
       $article,
       scalar($cgi->upload('image')),
       name => scalar($cgi->param('name')),
       alt => scalar($cgi->param('altIn')),
       url => scalar($cgi->param('url')),
       storage => scalar($cgi->param('storage')),
       errors => \%errors,
       filename => scalar($cgi->param("image")),
      );

  $imageobj
    or return $self->_service_error($req, $article, $articles, undef, \%errors);

  if ($save_tags) {
    my $error;
    $imageobj->set_tags([ grep /\S/, @tags ], \$error);
  }

  # typically a soft failure from the storage
  $errors{flash}
    and $req->flash($errors{flash});

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  if ($cgi->param('_service')) {
    return $self->_service_success
      (
       {
	image => $imageobj->{id},
       },
      );
  }
  elsif ($cgi->param("_") || $req->is_ajax) {
    my $resp = $req->json_content
      (
       success => 1,
       image => $self->_image_data($req->cfg, $imageobj),
      );

    # the browser handles this directly, tell it that it's text
    $resp->{type} = "text/plain";

    return $resp;
  }
  else {
    return $self->refresh($article, $cgi, undef, 'New image added');
  }
}

sub _image_manager {
  my ($self) = @_;

  require BSE::TB::Images;
  return BSE::TB::Images->storage_manager;
}

# remove an image
sub remove_img {
  my ($self, $req, $article, $articles, $imageid) = @_;

  $req->check_csrf("admin_remove_image")
    or return $self->csrf_error($req, $article, "admin_remove_image", "Remove Image");

  $req->user_can(edit_images_delete => $article)
    or return $self->_service_error($req, $article, $articles,
				 "You don't have access to delete images from this article", {}, "ACCESS");

  $imageid or die;

  my @images = $self->get_images($article);
  my ($image) = grep $_->{id} == $imageid, @images;
  unless ($image) {
    if ($req->want_json_response) {
      return $self->_service_error($req, $article, $articles, "No such image", {}, "NOTFOUND");
    }
    else {
      return $self->show_images($req, $article, $articles, "No such image");
    }
  }

  if ($image->{storage} ne 'local') {
    my $mgr = $self->_image_manager($req->cfg);
    $mgr->unstore($image->{image}, $image->{storage});
  }

  my $imagedir = cfg_image_dir($req->cfg);
  $image->remove;

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  if ($req->want_json_response) {
    return $req->json_content
      (
       success => 1,
      );
  }

  return $self->refresh($article, $req->cgi, undef, 'Image removed');
}

sub move_img_up {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_move_image")
    or return $self->csrf_error($req, $article, "admin_move_image", "Move Image");
  $req->user_can(edit_images_reorder => $article)
    or return $self->edit_form($req, $article, $articles,
				 "You don't have access to reorder images in this article");

  my $imageid = $req->cgi->param('imageid');
  my @images = $self->get_images($article);
  my ($imgindex) = grep $images[$_]{id} == $imageid, 0..$#images
    or return $self->edit_form($req, $article, $articles, "No such image");
  $imgindex > 0
    or return $self->edit_form($req, $article, $articles, "Image is already at the top");
  my ($to, $from) = @images[$imgindex-1, $imgindex];
  ($to->{displayOrder}, $from->{displayOrder}) =
    ($from->{displayOrder}, $to->{displayOrder});
  $to->save;
  $from->save;

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $req->cgi, undef, 'Image moved');
}

sub move_img_down {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_move_image")
    or return $self->csrf_error($req, $article, "admin_move_image", "Move Image");
  $req->user_can(edit_images_reorder => $article)
    or return $self->edit_form($req, $article, $articles,
				 "You don't have access to reorder images in this article");

  my $imageid = $req->cgi->param('imageid');
  my @images = $self->get_images($article);
  my ($imgindex) = grep $images[$_]{id} == $imageid, 0..$#images
    or return $self->edit_form($req, $article, $articles, "No such image");
  $imgindex < $#images
    or return $self->edit_form($req, $article, $articles, "Image is already at the end");
  my ($to, $from) = @images[$imgindex+1, $imgindex];
  ($to->{displayOrder}, $from->{displayOrder}) =
    ($from->{displayOrder}, $to->{displayOrder});
  $to->save;
  $from->save;

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  return $self->refresh($article, $req->cgi, undef, 'Image moved');
}

sub req_thumb {
  my ($self, $req, $article) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $im_id = $cgi->param('im');
  my $image;
  if (defined $im_id && $im_id =~ /^\d+$/) {
    ($image) = grep $_->{id} == $im_id, $self->get_images($article);
  }
  my $thumb_obj = $self->_get_thumbs_class();
  my ($data, $type);
  if ($image && $thumb_obj) {
    my $geometry_id = $cgi->param('g');
    defined $geometry_id or $geometry_id = 'editor';
    my $geometry = $cfg->entry('thumb geometries', $geometry_id, 'scale(200x200)');
    my $imagedir = cfg_image_dir();
    
    my $error;
    ($data, $type) = $thumb_obj->thumb_data
      (
       filename => "$imagedir/$image->{image}",
       geometry => $geometry,
       error => \$error
      )
	or return 
	  {
	   type => 'text/plain',
	   content => 'Error: '.$error
	  };
  }

  if ($type && $data) {
    
    return
      {
       type => $type,
       content => $data,
       headers => [ 
		   "Content-Length: ".length($data),
		   "Cache-Control: max-age=3600",
		  ],
      };
  }
  else {
    # grab the nothumb image
    my $uri = $cfg->entry('editor', 'default_thumbnail', cfg_dist_image_uri() . '/admin/nothumb.png');
    my $filebase = $cfg->content_base_path;
    if (open IMG, "<$filebase/$uri") {
      binmode IMG;
      my $data = do { local $/; <IMG> };
      close IMG;
      my $type = $uri =~ /\.(\w+)$/ ? $1 : 'png';
      return
	{
	 type => "image/$type",
	 content => $data,
	 headers => [ "Content-Length: ".length($data) ],
	};
    }
    else {
      return
	{
	 type=>"text/html",
	 content => "<html><body>Cannot make thumb or default image</body></html>",
	};
    }
  }
}

=item edit_image

Display a form to allow editing an image.

Tags:

=over

=item *

eimage - the image being edited

=item *

normal article edit tags.

=back

Variables:

eimage - the image being edited.

=cut

sub req_edit_image {
  my ($self, $req, $article, $articles, $errors) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('image_id');

  my ($image) = grep $_->{id} == $id, $self->get_images($article)
    or return $self->edit_form($req, $article, $articles,
			       "No such image");
  $req->user_can(edit_images_save => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to save image information for this article");

  $req->set_variable(eimage => $image);

  my %acts;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, $articles, undef,
			  $errors),
     eimage => [ \&tag_hash, $image ],
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return $req->response('admin/image_edit', \%acts);
}

=item a_save_image

Save changes to an image.

Parameters:

=over

=item *

id - article id

=item *

image_id - image id

=item *

alt, url, name - text fields to update

=item *

image - replacement image data (if any)

=back

=cut

sub req_save_image {
  my ($self, $req, $article, $articles) = @_;
  
  $req->check_csrf("admin_save_image")
    or return $self->csrf_error($req, $article, "admin_save_image", "Save Image");
  my $cgi = $req->cgi;

  my $id = $cgi->param('image_id');

  my @images = $self->get_images($article);
  my ($image) = grep $_->{id} == $id, @images
    or return $self->_service_error($req, $article, $articles, "No such image",
				    {}, "NOTFOUND");
  $req->user_can(edit_images_save => $article)
    or return $self->_service_error($req, $article, $articles,
				    "You don't have access to save image information for this article", {}, "ACCESS");

  my $image_dir = cfg_image_dir($req->cfg);

  my $old_storage = $image->{storage};

  my %errors;
  my $delete_file;
  my $alt = $cgi->param('alt');
  defined $alt and $image->{alt} = $alt;
  my $url = $cgi->param('url');
  defined $url and $image->{url} = $url;
  my @other_images = grep $_->{id} != $id, @images;
  my $name = $cgi->param('name');
  if (defined $name) {
    if (length $name) {
      if ($name !~ /^[a-z_]\w*$/i) {
	$errors{name} = 'Image name must be empty or alphanumeric and unique to the article';
      }
      elsif (grep $name eq $_->{name}, @other_images) {
	$errors{name} = 'Image name must be unique to the article';
      }
      else {
	$image->{name} = $name;
      }
    }
    else {
      $image->{name} = '';
    }
  }
  my $filename = $cgi->param('image');
  if (defined $filename && length $filename) {
    my $in_fh = $cgi->upload('image');
    if ($in_fh) {
      my $basename;
      my $image_error;
      my ($width, $height, $type) = $self->_validate_image
	($filename, $in_fh, \$basename, \$image_error);
      if ($type) {
	require DevHelp::FileUpload;
	my $msg;
	my ($image_name, $out_fh) = DevHelp::FileUpload->make_img_filename
	  ($image_dir, $basename, \$msg);
	if ($image_name) {
	  {
	    local $/ = \8192;
	    my $data;
	    while ($data = <$in_fh>) {
	      print $out_fh $data;
	    }
	    close $out_fh;
	  }

	  my $full_filename = "$image_dir/$image_name";
	  require Image::Size;
	  $delete_file = $image->{image};
	  $image->{image} = $image_name;
	  $image->{width} = $width;
	  $image->{height} = $height;
	  $image->{storage} = 'local'; # not on the remote store yet
	  $image->{src} = cfg_image_uri() . '/' . $image_name;
	  $image->{ftype} = $self->_image_ftype($type);
	}
	else {
	  $errors{image} = $msg;
	}
      }
      else {
	$errors{image} = $image_error;
      }
    }
    else {
      $errors{image} = "No image file received";
    }
  }
  my $save_tags = $cgi->param("_save_tags");
  my @tags;
  if ($save_tags) {
    @tags = $cgi->param("tags");
    $self->_validate_tags(\@tags, \%errors);
  }
  if (keys %errors) {
    if ($req->want_json_response) {
      return $self->_service_error($req, $article, $articles, undef,
				   \%errors, "FIELD");
    }
    else {
      return $self->req_edit_image($req, $article, $articles, \%errors);
    }
  }

  my $new_storage = $cgi->param('storage');
  defined $new_storage or $new_storage = $image->{storage};
  $image->save;
  if ($save_tags) {
    my $error;
    $image->set_tags([ grep /\S/, @tags ], \$error);
  }
  my $mgr = $self->_image_manager($req->cfg);
  if ($delete_file) {
    if ($old_storage ne 'local') {
      $mgr->unstore($delete_file, $old_storage);
    }
    unlink "$image_dir/$delete_file";
  }
  $req->flash("Image saved");
  eval {
    $new_storage = 
      $mgr->select_store($image->{image}, $new_storage);
    if ($image->{storage} ne $new_storage) {
      # handles both new images (which sets storage to local) and changing
      # the storage for old images
      my $old_storage = $image->{storage};
      my $src = $mgr->store($image->{image}, $new_storage, $image);
      $image->{src} = $src;
      $image->{storage} = $new_storage;
      $image->save;
    }
  };
  $@ and $req->flash("There was a problem adding it to the new storage: $@");
  if ($image->{storage} ne $old_storage && $old_storage ne 'local') {
    eval {
      $mgr->unstore($image->{image}, $old_storage);
    };
    $@ and $req->flash("There was a problem removing if from the old storage: $@");
  }

  if ($req->want_json_response) {
    return $req->json_content
      (
       success => 1,
       image => $self->_image_data($req->cfg, $image),
      );
  }

  return $self->refresh($article, $cgi);
}

=item a_order_images

Change the order of images for an article (or global images).

Ajax only.

=over

=item *

id - id of the article to change the image order for (-1 for global
images)

=item *

order - comma-separated list of image ids in the new order.

=back

=cut

sub req_order_images {
  my ($self, $req, $article, $articles) = @_;

  $req->is_ajax
    or return $self->_service_error($req, $article, $articles, "The function only permitted from Ajax", {}, "AJAXONLY");

  my $order = $req->cgi->param("order");
  defined $order
    or return $self->_service_error($req, $article, $articles, "order not supplied", {}, "NOORDER");
  $order =~ /^\d+(,\d+)*$/
    or return $self->_service_error($req, $article, $articles, "order not supplied", {}, "BADORDER");

  my @order = split /,/, $order;

  my @images = $article->set_image_order(\@order);

  return $req->json_content
    (
     success => 1,
     images =>
     [
      map $self->_image_data($req->cfg, $_), @images
     ],
    );
}

sub get_article {
  my ($self, $articles, $article) = @_;

  return $article;
}

sub table_object {
  my ($self, $articles) = @_;

  $articles;
}

sub _refresh_filelist {
  my ($self, $req, $article, $msg) = @_;

  return $self->refresh($article, $req->cgi, undef, $msg);
}

sub filelist {
  my ($self, $req, $article, $articles, $msg, $errors) = @_;

  my %acts;
  %acts = $self->low_edit_tags(\%acts, $req, $article, $articles, $msg, $errors);
  my $template = 'admin/filelist';

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

my %file_fields =
  (
   file => 
   {
    maxlength => MAX_FILE_DISPLAYNAME_LENGTH,
    description => 'Filename'
   },
   description =>
   {
    rules => 'dh_one_line',
    maxlength => 255,
    description => 'Description',
   },
   name =>
   {
    description => 'Identifier',
    maxlength => 80,
   },
   category =>
   {
    description => "Category",
    maxlength => 20,
   },
  );

sub fileadd {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_add_file")
    or return $self->csrf_error($req, $article, "admin_add_file", "Add File");
  $req->user_can(edit_files_add => $article)
    or return $self->_service_error($req, $article, $articles,
			      "You don't have access to add files to this article");

  my %file;
  my $cgi = $req->cgi;
  require BSE::TB::ArticleFiles;
  my @cols = BSE::TB::ArticleFile->columns;
  shift @cols;
  for my $col (@cols) {
    if (defined $cgi->param($col)) {
      $file{$col} = $cgi->param($col);
    }
  }

  my %errors;
  
  $req->validate(errors => \%errors,
		 fields => \%file_fields,
		 section => $article->{id} == -1 ? 'Global File Validation' : 'Article File Validation');
  
  # build a filename
  my $file = $cgi->upload('file');
  my $filename = $cgi->param("file");
  unless ($file) {
    $errors{file} = 'Please enter a filename';
  }
  if ($file && -z $file) {
    $errors{file} = 'File is empty';
  }
  
  $file{forSale}	= 0 + exists $file{forSale};
  $file{articleId}	= $article->{id};
  $file{download}	= 0 + exists $file{download};
  $file{requireUser}	= 0 + exists $file{requireUser};
  $file{hide_from_list} = 0 + exists $file{hide_from_list};
  $file{category}       ||= '';

  defined $file{name} or $file{name} = '';
  if (!$errors{name} && length $file{name} && $file{name} !~/^\w+$/) {
    $errors{name} = "Identifier must be a single word";
  }
  if (!$errors{name} && length $file{name}) {
    my @files = $self->get_files($article);
    if (grep lc $_->{name} eq lc $file{name}, @files) {
      $errors{name} = "Duplicate file identifier $file{name}";
    }
  }

  keys %errors
    and return $self->_service_error($req, $article, $articles, undef, \%errors);
  
  my $basename = '';
  my $workfile = $filename;
  $workfile =~ s![^\w.:/\\-]+!_!g;
  $workfile =~ tr/_/_/s;
  $workfile =~ /([ \w.-]+)$/ and $basename = $1;
  $basename =~ tr/ /_/;
  $file{displayName} = $basename;
  $file{file} = $file;

  local $SIG{__DIE__};
  my $fileobj = 
    eval {
      $article->add_file($self->cfg, %file);
    };

  $fileobj
    or return $self->_service_error($req, $article, $articles, $@);

  unless ($req->is_ajax) {
    $req->flash("New file added");
  }

  my $json =
    {
     success => 1,
     file => $fileobj->data_only,
     warnings => [],
    };
  my $storage = $cgi->param("storage") || "";
  eval {
    my $msg;

    $article->apply_storage($self->cfg, $fileobj, $storage, \$msg);

    if ($msg) {
      if ($req->is_ajax) {
	push @{$json->{warnings}}, $msg;
      }
      else {
	$req->flash_error($msg);
      }
    }
  };
  if ($@) {
    if ($req->is_ajax) {
      push @{$json->{warnings}}, $@;
    }
    else {
      $req->flash_error($@);
    }
  }

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  if ($req->is_ajax) {
    return $req->json_content($json);
  }
  else {
    $self->_refresh_filelist($req, $article);
  }
}

sub fileswap {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_move_file")
    or return $self->csrf_error($req, $article, "admin_move_file", "Move File");

  $req->user_can('edit_files_reorder', $article)
    or return $self->edit_form($req, $article, $articles,
			   "You don't have access to reorder files in this article");

  my $cgi = $req->cgi;
  my $id1 = $cgi->param('file1');
  my $id2 = $cgi->param('file2');

  if ($id1 && $id2) {
    my @files = $self->get_files($article);
    
    my ($file1) = grep $_->{id} == $id1, @files;
    my ($file2) = grep $_->{id} == $id2, @files;
    
    if ($file1 && $file2) {
      ($file1->{displayOrder}, $file2->{displayOrder})
	= ($file2->{displayOrder}, $file1->{displayOrder});
      $file1->save;
      $file2->save;
    }
  }

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->refresh($article, $req->cgi, undef, 'File moved');
}

sub filedel {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_remove_file")
    or return $self->csrf_error($req, $article, "admin_remove_file", "Delete File");
  $req->user_can('edit_files_delete', $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to delete files from this article");

  my $cgi = $req->cgi;
  my $fileid = $cgi->param('file');
  if ($fileid) {
    my @files = $self->get_files($article);

    my ($file) = grep $_->{id} == $fileid, @files;

    if ($file) {
      if ($file->{storage} ne 'local') {
	my $mgr = $self->_file_manager($self->cfg);
	$mgr->unstore($file->{filename}, $file->{storage});
      }

      $file->remove($req->cfg);
    }
  }

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->_refresh_filelist($req, $article, 'File deleted');
}

sub filesave {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_files")
    or return $self->csrf_error($req, $article, "admin_save_files", "Save Files");

  $req->user_can('edit_files_save', $article)
    or return $self->edit_form($req, $article, $articles,
			   "You don't have access to save file information for this article");
  my @files = $self->get_files($article);

  my $download_path = BSE::TB::ArticleFiles->download_path($self->{cfg});

  my $cgi = $req->cgi;
  my %names;
  my %errors;
  my @old_files;
  my @new_files;
  my %store_anyway;
  my $change_count = 0;
  my @content_changed;
  for my $file (@files) {
    my $id = $file->{id};
    my $orig = $file->data_only;
    my $desc = $cgi->param("description_$id");
    defined $desc and $file->{description} = $desc;
    my $type = $cgi->param("contentType_$id");
    if (defined $type and $type ne $file->{contentType}) {
      ++$store_anyway{$id};
      $file->{contentType} = $type;
    }
    my $notes = $cgi->param("notes_$id");
    defined $notes and $file->{notes} = $notes;
    my $category = $cgi->param("category_$id");
    defined $category and $file->{category} = $category;
    my $name = $cgi->param("name_$id");
    if (defined $name) {
      $file->{name} = $name;
      if (length $name) {
	if ($name =~ /^\w+$/) {
	  push @{$names{$name}}, $id;
	}
	else {
	  $errors{"name_$id"} = "Invalid file identifier $name";
	}
      }
    }
    else {
      push @{$names{$file->{name}}}, $id
	if length $file->{name};
    }
    if ($cgi->param('save_file_flags')) {
      my $download = 0 + defined $cgi->param("download_$id");
      if ($download != $file->{download}) {
	++$store_anyway{$file->{id}};
	$file->{download}	      = $download;
      }
      $file->{forSale}	      = 0 + defined $cgi->param("forSale_$id");
      $file->{requireUser}    = 0 + defined $cgi->param("requireUser_$id");
      $file->{hide_from_list} = 0 + defined $cgi->param("hide_from_list_$id");
    }

    my $filex = $cgi->param("file_$id");
    my $in_fh = $cgi->upload("file_$id");
    if (defined $filex && length $filex) {
      if (length $filex <= MAX_FILE_DISPLAYNAME_LENGTH) {
	if ($in_fh) {
	  if (-s $in_fh) {
	    require DevHelp::FileUpload;
	    my $msg;
	    my ($file_name, $out_fh) = DevHelp::FileUpload->make_img_filename
	      ($download_path, $filex . '', \$msg);
	    if ($file_name) {
	      {
		local $/ = \8192;
		my $data;
		while ($data = <$in_fh>) {
		  print $out_fh $data;
		}
		close $out_fh;
	      }
	      my $display_name = $filex;
	      $display_name =~ s!.*[\\:/]!!;
	      $display_name =~ s/[^\w._-]+/_/g;
	      my $full_name = "$download_path/$file_name";
	      push @old_files, [ $file->{filename}, $file->{storage} ];
	      push @new_files, $file_name;
	      
	      $file->{filename} = $file_name;
	      $file->{storage} = 'local';
	      $file->{sizeInBytes} = -s $full_name;
	      $file->{whenUploaded} = now_sqldatetime();
	      $file->{displayName} = $display_name;
	      push @content_changed, $file;
	    }
	    else {
	      $errors{"file_$id"} = $msg;
	    }
	  }
	  else {
	    $errors{"file_$id"} = "File is empty";
	  }
	}
	else {
	  $errors{"file_$id"} = "No file data received";
	}
      }
      else {
	$errors{"file_$id"} = "Filename too long";
      }
    }

    my $new = $file->data_only;
  COLUMN:
    for my $col ($file->columns) {
      if ($new->{$col} ne $orig->{$col}) {
	++$change_count;
	last COLUMN;
      }
    }
  }
  for my $name (keys %names) {
    if (@{$names{$name}} > 1) {
      for my $id (@{$names{$name}}) {
	$errors{"name_$id"} = 'File identifier must be unique to the article';
      }
    }
  }
  if (keys %errors) {
    # remove the uploaded replacements
    unlink map "$download_path/$_", @new_files;

    return $self->edit_form($req, $article, $articles, undef, \%errors);
  }
  if ($change_count) {
    $req->flash("msg:bse/admin/edit/file/save/success_count", [ $change_count ]);
  }
  else {
    $req->flash("msg:bse/admin/edit/file/save/success_none");
  }
  my $mgr = $self->_file_manager($self->cfg);
  for my $file (@files) {
    $file->save;

    my $storage = $cgi->param("storage_$file->{id}");
    defined $storage or $storage = 'local';
    my $msg;
    $storage = $article->select_filestore($mgr, $file, $storage, \$msg);
    $msg and $req->flash($msg);
    if ($storage ne $file->{storage} || $store_anyway{$file->{id}}) {
      my $old_storage = $file->{storage};
      eval {
	$file->{src} = $mgr->store($file->{filename}, $storage, $file);
	$file->{storage} = $storage;
	$file->save;

	if ($old_storage ne $storage) {
	  $mgr->unstore($file->{filename}, $old_storage);
	}
      };
      $@
	and $req->flash("Could not move $file->{displayName} to $storage: $@");
    }
  }

  # remove the replaced files
  for my $file (@old_files) {
    my ($filename, $storage) = @$file;

    eval {
      $mgr->unstore($filename, $storage);
    };
    $@
      and $req->flash("Error removing $filename from $storage: $@");

    unlink "$download_path/$filename";
  }

  # update file type metadatas
  for my $file (@content_changed) {
    $file->set_handler($self->{cfg});
    $file->save;
  }

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->_refresh_filelist($req, $article);
}

sub req_filemeta {
  my ($self, $req, $article, $articles, $errors) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('file_id');

  my ($file) = grep $_->{id} == $id, $self->get_files($article)
    or return $self->edit_form($req, $article, $articles,
			       "No such file");
  $req->user_can(edit_files_save => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to save file information for this article");

  my $name = $cgi->param('name');
  $name && $name =~ /^\w+$/
    or return $self->edit_form($req, $article, $articles,
			       "Missing or invalid metadata name");

  my $meta = $file->meta_by_name($name)
    or return $self->edit_form($req, $article, $articles,
			       "Metadata $name not defined for this file");

  return
    {
     type => $meta->content_type,
     content => $meta->value,
    };
}

sub tag_old_checked {
  my ($errors, $cgi, $file, $key) = @_;

  return $errors ? $cgi->param($key) : $file->{$key};
}

sub tag_filemeta_value {
  my ($file, $args, $acts, $funcname, $templater) = @_;

  my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater)
    or return "* no meta name supplied *";

  my $meta = $file->meta_by_name($name)
    or return "";

  $meta->content_type eq "text/plain"
    or return "* $name has type " . $meta->content_type . " and cannot be displayed inline *";

  return escape_html($meta->value);
}

sub tag_ifFilemeta_set {
  my ($file, $args, $acts, $funcname, $templater) = @_;

  my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater)
    or return "* no meta name supplied *";

  my $meta = $file->meta_by_name($name)
    or return 0;

  return 1;
}

sub tag_filemeta_source {
  my ($file, $args, $acts, $funcname, $templater) = @_;

  my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater)
    or return "* no meta name supplied *";

  return "$ENV{SCRIPT_NAME}?a_filemeta=1&amp;id=$file->{articleId}&amp;file_id=$file->{id}&amp;name=$name";
}

sub tag_filemeta_select {
  my ($cgi, $allmeta, $rcurr_meta, $file, $args, $acts, $funcname, $templater) = @_;

  my $meta;
  if ($args =~ /\S/) {
    my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater)
      or return "* cannot parse *";
    ($meta) = grep $_->name eq $name, @$allmeta
      or return "* cannot find meta field *";
  }
  elsif ($$rcurr_meta) {
    $meta = $$rcurr_meta;
  }
  else {
    return "* use in filemeta iterator or supply a name *";
  }

  $meta->type eq "enum"
    or return "* can only use filemeta_select on enum metafields *";

  my %labels;
  my @values = $meta->values;
  @labels{@values} = $meta->labels;

  my $field_name = "meta_" . $meta->name;
  my ($def) = $cgi->param($field_name);
  unless (defined $def) {
    my $value = $file->meta_by_name($meta->name);
    if ($value && $value->is_text) {
      $def = $value->value;
    }
  }
  defined $def or $def = $values[0];

  return popup_menu
    (
     -name => $field_name,
     -values => \@values,
     -labels => \%labels,
     -default => $def,
    );
}

sub tag_filemeta_select_label {
  my ($allmeta, $rcurr_meta, $file, $args, $acts, $funcname, $templater) = @_;

  my $meta;
  if ($args =~ /\S/) {
    my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater)
      or return "* cannot parse *";
    ($meta) = grep $_->name eq $name, @$allmeta
      or return "* cannot find meta field *";
  }
  elsif ($$rcurr_meta) {
    $meta = $$rcurr_meta;
  }
  else {
    return "* use in filemeta iterator or supply a name *";
  }

  $meta->type eq "enum"
    or return "* can only use filemeta_select_label on enum metafields *";

  my %labels;
  my @values = $meta->values;
  @labels{@values} = $meta->labels;

  my $field_name = "meta_" . $meta->name;
  my $value = $file->meta_by_name($meta->name);
  if ($value) {
    if ($value->is_text) {
      if (exists $labels{$value->value}) {
	return escape_html($labels{$value->value});
      }
      else {
	return escape_html($value->value);
      }
    }
    else {
      return "* cannot display type " . $value->content_type . " inline *";
    }
  }
  else {
    return "* " . $meta->name . " not set *";
  }
}

sub req_edit_file {
  my ($self, $req, $article, $articles, $errors) = @_;

  my $cgi = $req->cgi;

  my $id = $cgi->param('file_id');

  my ($file) = grep $_->{id} == $id, $self->get_files($article)
    or return $self->edit_form($req, $article, $articles,
			       "No such file");
  $req->user_can(edit_files_save => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to save file information for this article");

  my @metafields = $file->metafields($self->cfg);

  my $it = BSE::Util::Iterate->new;
  my $current_meta;
  my %acts;
  %acts =
    (
     $self->low_edit_tags(\%acts, $req, $article, $articles, undef,
			  $errors),
     efile => [ \&tag_object, $file ],
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     ifOldChecked =>
     [ \&tag_old_checked, $errors, $cgi, $file ],
     $it->make
     (
      plural => "filemetas",
      single => "filemeta",
      data => \@metafields,
      store => \$current_meta,
     ),
     filemeta_value =>
     [ \&tag_filemeta_value, $file ],
     ifFilemeta_set =>
     [ \&tag_ifFilemeta_set, $file ],
     filemeta_source =>
     [ \&tag_filemeta_source, $file ],
     filemeta_select =>
     [ \&tag_filemeta_select, $cgi, \@metafields, \$current_meta, $file ],
     filemeta_select_label =>
     [ \&tag_filemeta_select_label, \@metafields, \$current_meta, $file ],
    );

  return $req->response('admin/file_edit', \%acts);
}

sub req_save_file {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_file")
    or return $self->csrf_error($req, $article, "admin_save_file", "Save File");

  my $cgi = $req->cgi;

  my @files = $self->get_files($article);
  
  my $id = $cgi->param('file_id');

  my ($file) = grep $_->{id} == $id, @files
    or return $self->edit_form($req, $article, $articles,
			       "No such file");
  $req->user_can(edit_files_save => $article)
    or return $self->edit_form($req, $article, $articles,
			       "You don't have access to save file information for this article");
  my @other_files = grep $_->{id} != $id, @files;

  my $download_path = BSE::TB::ArticleFiles->download_path($self->{cfg});

  my %errors;

  $req->validate(errors => \%errors,
		 fields => \%file_fields,
		 section => $article->{id} == -1 ? 'Global File Validation' : 'Article File Validation');

  my $store_anyway = 0;
  my $desc = $cgi->param("description");
  defined $desc and $file->{description} = $desc;
  my $type = $cgi->param("contentType");
  if (defined $type && $file->{contentType} ne $type) {
    ++$store_anyway;
    $file->{contentType} = $type;
  }
  my $notes = $cgi->param("notes");
  defined $notes and $file->{notes} = $notes;
  my $name = $cgi->param("name");
  if (defined $name) {
    $file->{name} = $name;
    if (length $name) {
      if ($name =~ /^\w+$/) {
	if (grep lc $name eq lc $_->{name}, @other_files) {
	  $errors{name} = 'File identifier must be unique to the article';
	}
      }
      else {
	$errors{name} = "Invalid file identifier $name";
      }
    }
  }

  my @meta;
  my @meta_delete;
  my @metafields = grep !$_->ro, $file->metafields($self->cfg);
  my %current_meta = map { $_ => 1 } $file->metanames;
  for my $meta (@metafields) {
    my $name = $meta->name;
    my $cgi_name = "meta_$name";
    if ($cgi->param("delete_$cgi_name")) {
      for my $metaname ($meta->metanames) {
	push @meta_delete, $metaname
	  if $current_meta{$metaname};
      }
    }
    else {
      my $new;
      if ($meta->is_text) {
	my ($value) = $cgi->param($cgi_name);
	if (defined $value && 
	    ($value =~ /\S/ || $current_meta{$meta->name})) {
	  my $error;
	  if ($meta->validate(value => $value, error => \$error)) {
	    push @meta,
	      {
	       name => $name,
	       value => $value,
	      };
	  }
	  else {
	    $errors{$cgi_name} = $error;
	  }
	}
      }
      else {
	my $im = $cgi->param($cgi_name);
	my $up = $cgi->upload($cgi_name);
	if (defined $im && $up) {
	  my $data = do { local $/; <$up> };
	  my ($width, $height, $type) = imgsize(\$data);

	  if ($width && $height) {
	    push @meta,
	      (
	       {
		name => $meta->data_name,
		value => $data,
		content_type => "image/\L$type",
	       },
	       {
		name => $meta->width_name,
		value => $width,
	       },
	       {
		name => $meta->height_name,
		value => $height,
	       },
	      );
	  }
	  else {
	    $errors{$cgi_name} = $type;
	  }
	}
      }
    }
  }

  if ($cgi->param('save_file_flags')) {
    my $download = 0 + defined $cgi->param("download");
    if ($download ne $file->{download}) {
      ++$store_anyway;
      $file->{download}	    = $download;
    }
    $file->{forSale}	    = 0 + defined $cgi->param("forSale");
    $file->{requireUser}    = 0 + defined $cgi->param("requireUser");
    $file->{hide_from_list} = 0 + defined $cgi->param("hide_from_list");
  }
  
  my @old_file;
  my @new_files;
  my $filex = $cgi->param("file");
  my $in_fh = $cgi->upload("file");
  if (defined $filex && length $filex) {
    if ($in_fh) {
      if (-s $in_fh) {
	require DevHelp::FileUpload;
	my $msg;
	my ($file_name, $out_fh) = DevHelp::FileUpload->make_img_filename
	  ($download_path, $filex . '', \$msg);
	if ($file_name) {
	  {
	    local $/ = \8192;
	    my $data;
	    while ($data = <$in_fh>) {
	      print $out_fh $data;
	    }
	    close $out_fh;
	  }
	  my $display_name = $filex;
	  $display_name =~ s!.*[\\:/]!!;
	  $display_name =~ s/[^\w._-]+/_/g;
	  my $full_name = "$download_path/$file_name";
	  @old_file = ( $file->{filename}, $file->{storage} );
	  push @new_files, $file_name;
	  
	  $file->{filename} = $file_name;
	  $file->{sizeInBytes} = -s $full_name;
	  $file->{whenUploaded} = now_sqldatetime();
	  $file->{displayName} = $display_name;
	  $file->{storage} = 'local';
	}
	else {
	  $errors{"file"} = $msg;
	}
      }
      else {
	$errors{"file"} = "File is empty";
      }
    }
    else {
      $errors{"file"} = "No file data received";
    }
  }

  if (keys %errors) {
    # remove the uploaded replacements
    unlink map "$download_path/$_", @new_files;

    return $self->req_edit_file($req, $article, $articles, \%errors);
  }
  $file->save;

  $file->set_handler($self->cfg);
  $file->save;

  $req->flash("msg:bse/admin/edit/file/save/success", [ $file->displayName ]);
  my $mgr = $self->_file_manager($self->cfg);

  my $storage = $cgi->param('storage');
  defined $storage or $storage = $file->{storage};
  my $msg;
  $storage = $article->select_filestore($mgr, $file, $storage, \$msg);
  $msg and $req->flash($msg);
  if ($storage ne $file->{storage} || $store_anyway) {
    my $old_storage = $file->{storage};
    eval {
      $file->{src} = $mgr->store($file->{filename}, $storage, $file);
      $file->{storage} = $storage;
      $file->save;

      $mgr->unstore($file->{filename}, $old_storage)
	if $old_storage ne $storage;
    };
    $@
      and $req->flash("Could not move $file->{displayName} to $storage: $@");
  }

  for my $meta_delete (@meta_delete, map $_->{name}, @meta) {
    $file->delete_meta_by_name($meta_delete);
  }
  for my $meta (@meta) {
    $file->add_meta(%$meta, appdata => 1);
  }

  # remove the replaced files
  if (my ($old_name, $old_storage) = @old_file) {
    $mgr->unstore($old_name, $old_storage);
    unlink "$download_path/$old_name";
  }

  generate_article($articles, $article) if $Constants::AUTO_GENERATE;

  $self->_refresh_filelist($req, $article);
}

sub can_remove {
  my ($self, $req, $article, $articles, $rmsg, $rcode) = @_;

  unless ($req->user_can('edit_delete_article', $article, $rmsg)) {
    $$rmsg ||= "Access denied";
    $$rcode = "ACCESS";
    return;
  }

  if ($articles->children($article->{id})) {
    $$rmsg = "This article has children.  You must delete the children first (or change their parents)";
    $$rcode = "CHILDREN";
    return;
  }
  if (grep($_ == $article->{id}, @Constants::NO_DELETE)
     || $req->cfg->entry("undeletable articles", $article->{id})) {
    $$rmsg = "Sorry, these pages are essential to the site structure - they cannot be deleted";
    $$rcode = "ESSENTIAL";
    return;
  }
  if ($article->{id} == $Constants::SHOPID) {
    $$rmsg = "Sorry, these pages are essential to the store - they cannot be deleted - you may want to hide the store instead.";
    $$rcode = "SHOP";
    return;
  }

  return 1;
}

=item remove

Error codes:

=over

=item *

ACCESS - access denied

=item *

CHILDREN - the article has children

=item *

ESSENTIAL - the article is marked essential

=item *

SHOP - the article is an essential part of the shop (the shop article
itself)

=back

JSON success response: { success: 1, article_id: I<id> }

=cut

sub remove {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_remove_article")
    or return $self->csrf_error($req, $article, "admin_remove_article", "Remove Article");

  my $why_not;
  my $code;
  unless ($self->can_remove($req, $article, $articles, \$why_not, \$code)) {
    return $self->_service_error($req, $article, $articles, $why_not, {}, $code);
  }

  my $data = $article->data_only;

  my $parentid = $article->{parentid};
  $article->remove($req->cfg);

  if ($req->is_ajax) {
    return $req->json_content
      (
       success => 1,
       article_id => $data->{id},
      );
  }

  my $url = $req->cgi->param('r');
  unless ($url) {
    $url = $req->cfg->admin_url("add", { id => $parentid });
  }

  $req->flash_notice("msg:bse/admin/edit/remove", [ $data ]);

  return BSE::Template->get_refresh($url, $self->{cfg});
}

sub unhide {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_article")
    or return $self->csrf_error($req, $article, "admin_save_article", "Unhide article");

  if ($req->user_can(edit_field_edit_listed => $article)
      && $req->user_can(edit_save => $article)) {
    $article->{listed} = 1;
    $article->save;

    generate_article($articles, $article) if $Constants::AUTO_GENERATE;
  }
  return $self->refresh($article, $req->cgi, undef, 'Article unhidden');
}

sub hide {
  my ($self, $req, $article, $articles) = @_;

  $req->check_csrf("admin_save_article")
    or return $self->csrf_error($req, $article, "admin_save_article", "Hide article");

  if ($req->user_can(edit_field_edit_listed => $article)
      && $req->user_can(edit_save => $article)) {
    $article->{listed} = 0;
    $article->save;

    generate_article($articles, $article) if $Constants::AUTO_GENERATE;
  }
  my $r = $req->cgi->param('r');
  unless ($r) {
    $r = admin_base_url($req->cfg)
      . "/cgi-bin/admin/add.pl?id=" . $article->{parentid};
  }
  return $self->refresh($article, $req->cgi, undef, 'Article hidden');
}

my %defaults =
  (
   titleImage => '',
   imagePos => 'tr',
   expire => $Constants::D_99,
   listed => 1,
   keyword => '',
   body => '<maximum of 64Kb>',
   force_dynamic => 0,
   inherit_siteuser_rights => 1,
   menu => 0,
   titleAlias => '',
   linkAlias => '',
   author => '',
   summary => '',
   category => '',
  );

sub default_value {
  my ($self, $req, $article, $col) = @_;

  if ($article->{parentid}) {
    my $section = "children of $article->{parentid}";
    my $value = $req->cfg->entry($section, $col);
    if (defined $value) {
      return $value;
    }
  }
  my $section = "level $article->{level}";
  my $value = $req->cfg->entry($section, $col);
  defined($value) and return $value;

  $value = $self->type_default_value($req, $col);
  defined $value and return $value;

  exists $defaults{$col} and return $defaults{$col};

  $col eq 'release' and return now_sqldate();

  if ($col eq 'threshold') {
    my $parent = defined $article->{parentid} && $article->{parentid} != -1 
      && Articles->getByPkey($article->{parentid}); 

    $parent and return $parent->{threshold};
    
    return 5;
  }
  
  if ($col eq 'summaryLength') {
    my $parent = defined $article->{parentid} && $article->{parentid} != -1 
      && Articles->getByPkey($article->{parentid}); 

    $parent and return $parent->{summaryLength};
    
    return 200;
  }
  
  return;
}

sub type_default_value {
  my ($self, $req, $col) = @_;

  return $req->cfg->entry('article defaults', $col);
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

sub get_images {
  my ($self, $article) = @_;

  $article->images;
}

sub validate_image_name {
  my ($self, $name, $rmsg) = @_;

  1; # no extra validation
}

sub req_ajax_get {
  my ($self, $req, $article, $articles, @extras) = @_;

  my $field_name = $req->cgi->param('field');
  unless ($field_name && exists $article->{$field_name}) {
    print STDERR "req_ajax_get: missing or invalid field parameter\n";
    return {
	    content => 'Invalid or missing field name',
	    headers => [
			"Status: 187" # bad request
		       ],
	   };
  }

  my $value = $article->{$field_name};
  defined $value or $value = '';

  my $charset = $req->cfg->entry('html', 'charset', 'iso-8859-1');
  
  # re-encode to utf8
  require Encode;
  Encode::from_to($value, $charset, 'utf8');

  # make some content
  return
    {
     content => $value,
     type => 'text/plain; charset=utf-8',
    };
}

sub req_ajax_save_body {
   my ($self, $req, $article, $articles, @extras) = @_;

   my $cfg = $req->cfg;
   my $cgi = $req->cgi;

   unless ($req->user_can("edit_save", $article)
	   && $req->user_can("edit_field_edit_body", $article)) {
    return {
	    content => "Access denied to body",
	    headers => [
			"Status: 187" # bad request
		       ],
	   };
   }

   require Encode;
   # ajax always sends in UTF-8
   my $body = Encode::decode(utf8 => $cgi->param('body'));

   my $charset = $req->cfg->entry('html', 'charset', 'iso-8859-1');
  
   # convert it to our working charset
   # any characters that don't convert are replaced by some 
   # substitution character, not defined by the documentation
   $body = Encode::encode($charset, $body);

   $article->{body} = $body;
   $article->{lastModified} = now_sqldatetime();
   my $user = $req->getuser;
   $article->{lastModifiedBy} = $user ? $user->{logon} : '';
   $article->save;

   my @extra_regen;
   @extra_regen = $self->update_child_dynamic($article, $articles, $req);

   if ($Constants::AUTO_GENERATE) {
     require Util;
     generate_article($articles, $article);
     for my $regen_id (@extra_regen) {
       my $regen = $articles->getByPkey($regen_id);
       BSE::Regen::generate_low($articles, $regen, $self->{cfg});
     }
   }
 
   # we need the formatted body as the result
   my $genname = $article->{generator};
   eval "use $genname";
   $@ and die "Error on use $genname: $@";
   my $gen = $genname->new(article => $articles, cfg => $cfg, top => $article);
   my %acts;
   %acts = $gen->baseActs($articles, \%acts, $article, 0);
   my $template = "<:body:>";
   my $formatted = BSE::Template->replace($template, $req->cfg, \%acts);

   return
     {
      content => $formatted,
      type => BSE::Template->html_type($cfg),
     };
}

sub iter_file_metas {
  my ($self, $files, $rfile_index) = @_;

  $$rfile_index < 0 || $$rfile_index >= @$files
    and return;

  my $file = $files->[$$rfile_index];

  return $file->text_metadata;
}

my %settable_fields = qw(title keyword author pageTitle);
  

sub req_ajax_set {
   my ($self, $req, $article, $articles, @extras) = @_;

   my $cfg = $req->cfg;
   my $cgi = $req->cgi;

   my $field = $cgi->param('field');

   unless ($field && $settable_fields{$field}) {
    return {
	    content => 'Invalid or missing field name',
	    headers => [
			"Status: 187" # bad request
		       ],
	   };
   }
   unless ($req->user_can("edit_save", $article)
	   && $req->user_can("edit_field_edit_$field", $article)) {
    return {
	    content => "Access denied to $field",
	    headers => [
			"Status: 187" # bad request
		       ],
	   };
   }

   require Encode;
   # ajax always sends in UTF-8
   my $value = Encode::decode(utf8 => $cgi->param('value'));

   # hack - validate it if it's the title
   if ($field eq 'title') {
     if ($value !~ /\S/) {
       return {
	       content => 'Invelid or missing field name',
	       headers => [
			   "Status: 187" # bad request
			  ],
	      };
     }
   }

   my $charset = $req->cfg->entry('html', 'charset', 'iso-8859-1');
  
   # convert it to our working charset
   # any characters that don't convert are replaced by some 
   # substitution character, not defined by the documentation
   $value = Encode::encode($charset, $value);

   $article->{$field} = $value;
   $article->{lastModified} = now_sqldatetime();
   my $user = $req->getuser;
   $article->{lastModifiedBy} = $user ? $user->{logon} : '';
   $article->save;

   my @extra_regen;
   @extra_regen = $self->update_child_dynamic($article, $articles, $req);

   if ($Constants::AUTO_GENERATE) {
     require Util;
     generate_article($articles, $article);
     for my $regen_id (@extra_regen) {
       my $regen = $articles->getByPkey($regen_id);
       BSE::Regen::generate_low($articles, $regen, $self->{cfg});
     }
   }
 
   return
     {
      content => $value,
      type => BSE::Template->html_type($cfg),
     };
}

sub csrf_error {
  my ($self, $req, $article, $name, $description) = @_;

  my %errors;
  my $msg = $req->csrf_error;
  $errors{_csrfp} = $msg;
  my $mymsg;
  $article ||= $self->_dummy_article($req, 'Articles', \$mymsg);
  unless ($article) {
    require BSE::Edit::Site;
    my $site = BSE::Edit::Site->new(cfg=>$req->cfg, db=> BSE::DB->single);
    return $site->edit_sections($req, 'Articles', $mymsg);
  }
  return $self->_service_error($req, $article, 'Articles', $msg, \%errors);
}

=item a_csrp

Returns the csrf token for a given action.

Must only be callable from Ajax requests.

In general Ajax requests won't require a token, but some types of
requests initiated by an Ajax based client might need a token, in
particular: file uploads.

=cut

sub req_csrfp {
  my ($self, $req, $article, $articles) = @_;

  $req->is_ajax
    or return $self->_service_error($req, $article, $articles,
				    "Only usable from Ajax", undef, "NOTAJAX");

  $ENV{REQUEST_METHOD} eq 'POST'
    or return $self->_service_error($req, $article, "Articles",
				    "POST required for this action", {}, "NOTPOST");

  my %errors;
  my (@names) = $req->cgi->param("name");
  @names or $errors{name} = "Missing parameter 'name'";
  unless ($errors{name}) {
    for my $name (@names) {
      $name =~ /^\w+\z/
	or $errors{name} = "Invalid name: must be an identifier";
    }
  }

  keys %errors
    and return $self->_service_error($req, $article, $articles,
				     "Invalid parameter", \%errors, "FIELD");

  return $req->json_content
    (
     {
      success => 1,
      tokens =>
      {
       map { $_ => $req->get_csrf_token($_) } @names,
      },
     },
    );
}

sub _article_kid_summary {
  my ($article_id, $depth) = @_;

  my @kids = BSE::DB->query(bseArticleKidSummary => $article_id);
  if (--$depth > 0) {
    for my $kid (@kids) {
      $kid->{children} = [ _article_kid_summary($kid->{id}, $depth) ];
      $kid->{allkids} = [ Articles->allkid_summary($kid->{id}) ];
    }
  }

  return @kids;
}

=item a_tree

Returns a JSON tree of articles.

Requires an article id (-1 to start from the root).

Takes an optional tree depth.  1 only shows immediate children of the
article.

=cut

sub req_tree {
  my ($self, $req, $article, $articles) = @_;

  my $depth = $req->cgi->param("depth");
  defined $depth && $depth =~ /^\d+$/ and $depth >= 1
    or $depth = 10000; # something large

  $req->is_ajax
    or return $self->_service_error($req, $article, $articles, "Only available to Ajax requests", {}, "NOTAJAX");

  return $req->json_content
    (
     success => 1,
     articles =>
     [
      _article_kid_summary($article->id, $depth),
     ],
     allkids =>
     [
      Articles->allkid_summary($article->id)
     ],
    );
}

=item a_article

Returns the article as JSON.

Populates images with images and files with files.

The article data is in the article member of the returned object.

=cut

sub req_article {
  my ($self, $req, $article, $articles) = @_;

  $req->is_ajax
    or return $self->_service_error($req, $article, $articles, "Only available to Ajax requests", {}, "NOTAJAX");

  return $req->json_content
    (
     success => 1,
     article => $self->_article_data($req, $article),
    );
}

sub templates_long {
  my ($self, $article) = @_;

  my @templates = $self->templates($article);

  my $cfg = $self->{cfg};
  return map
    +{
      name => $_,
      description => $cfg->entry("template descriptions", $_, $_),
     }, @templates;
}

sub _populate_config {
  my ($self, $req, $article, $articles, $conf) = @_;

  my $cfg = $req->cfg;
  my %geos = $cfg->entries("thumb geometries");
  my %defaults;
  my @cols = $self->table_object($articles)->rowClass->columns;
  shift @cols;
  for my $col (@cols) {
    my $def = $self->default_value($req, $article, $col);
    defined $def and $defaults{$col} = $def;
  }
  my @templates = $self->templates($article);
  $defaults{template} =
    $self->default_template($article, $req->cfg, \@templates);

  $conf->{templates} = [ $self->templates_long($article) ];
  $conf->{thumb_geometries} =
    [
     map
     {
       +{
	 name => $_,
	 description => $cfg->entry("thumb geometry $_", "description", $_),
	};
     } sort keys %geos
    ];
  $conf->{defaults} = \%defaults;
  $conf->{upload_progress} = $req->_tracking_uploads;
  my @child_types = $self->child_types($article);
  s/^BSE::Edit::// for @child_types;
  $conf->{child_types} = \@child_types;
  $conf->{flags} = [ $self->flags ];
}

=item a_config

Returns configuration information as JSON.

Returns an object of the form:

  {
    success: 1,
    templates:
    [
      "template.tmpl":
      {
        description: "template.tmpl", // or from [template descriptions]
      },
      ...
    ],
    thumb_geometries:
    [
      "geoid":
      {
        description: "geoid", // or from [thumb geometry id].description
      },
    ],
    defaults:
    {
      field: value,
      ...
    },
    child_types: [ "Article" ],
    flags:
    [
      { id => "A", desc => "description" },
      ...
    ],
    // possibible custom data
  }

To define custom data add entries to the [extra a_config] section,
keys become the keys in the returned structure pointing at hashes
containing that section from the system configuration.  Custom keys
may not conflict with system defined keys.

=cut

sub req_config {
  my ($self, $req, $article, $articles) = @_;
  
  $req->is_ajax
    or return $self->_service_error($req, $article, $articles, "Only available to Ajax requests", {}, "NOTAJAX");

  my %conf;
  $self->_populate_config($req, $article, $articles, \%conf);
  $conf{success} = 1;

  my $cfg = $req->cfg;
  my %custom = $cfg->entries("extra a_config");
  for my $key (keys %custom) {
    exists $conf{$key} and next;

    my $section = $custom{$key};
    $section =~ s/\{(level|generator|parentid|template)\}/$article->{$1}/g;

    $section eq "db" and die;

    $conf{$key} = { $cfg->entries($section) };
  }

  return $req->json_content
    (
     \%conf
    );
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 REVISION 

$Revision$

=cut
