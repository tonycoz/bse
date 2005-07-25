package BSE::UI::Page;
use strict;
use Articles;
use DevHelp::HTML qw(escape_uri);

# we don't do anything fancy on dispatch yet, so don't use the 
# dispatch classes
sub dispatch {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  $id && $id =~ /^\d+$/
    or return $class->error($req, "required id parameter not present or invalid");
  my $article = Articles->getByPkey($id)
    or return $class->error($req, "unknown article id $id");

  # get the dynamic generate for this article type
  my $gen_class = $article->{generator};
  $gen_class =~ s/.*\W//;
  $gen_class = "BSE::Dynamic::".$gen_class;
  (my $gen_file = $gen_class . ".pm") =~ s!::!/!g;
  eval {
    require $gen_file;
  };
  $@ and return $class->error($req, $@);
  my $gen = $gen_class->new($req);
  $article = $gen->get_real_article($article)
    or return $class->error($req, "Cannot get full article for $id");

  $article->is_dynamic
    or print STDERR "** page.pl called for non-dynamic article $id\n";

  my $cfg = $req->cfg;

  unless ($class->has_access($req, $article)) {
    if ($req->siteuser) {
      return $class->error
	($req, "You do not have access to view this article");
    }
    else {
      my $refresh = $article->{link};
      my $logon =
	$cfg->entry('site', 'url') . "/cgi-bin/user.pl?show_logon=1&r=".escape_uri($refresh)."&message=You+need+to+logon+to+view+this+article";
      return BSE::Template->get_refresh($logon, $cfg);
    }
  }

  my $dynamic_path = $cfg->entryVar('paths', 'dynamic_cache');
  my $debug_jit = $cfg->entry('debug', 'jit_dynamic_regen');
  my $srcname = $dynamic_path . "/" . $article->{id} . ".html";
  my $dynamic_pregen = $cfg->entry('basic', 'jit_dynamic_pregen');
  my $template;
  if (-e $srcname) {
    if (open SRC, "< $srcname") {
      local $/;
      $template = <SRC>;
      close SRC;
    }
    else {
      print STDERR "** PAGE: $id - page file exists but isn't readable\n";
    }
  }
  unless (defined $template) {
    $debug_jit && !$dynamic_pregen
      and print STDERR "** JIT: $id - pregen page not found but JIT off\n";
    
    $template = $class->_generate_pregen($req, $article, $srcname);
  }

  return $gen->generate($article, $template);
}

# returns an error page
sub error {
  my ($class, $req, $msg) = @_;

  require BSE::UI::Dispatch;
  return BSE::UI::Dispatch->error($req, { error => $msg });
}

sub _generate_pregen {
  my ($class, $req, $article, $srcname) = @_;

  my $articles = 'Articles';
  my $genname = $article->{generator};
  eval "use $genname";
  $@ && die $@;
  my $gen = $genname->new(articles=>$articles, cfg=>$req->cfg, top=>$article);

  my $content = $gen->generate($article, $articles);

  if (open CONTENT, "> $srcname") {
    binmode CONTENT;
    print CONTENT $content;
    close CONTENT;
  }
  else {
    print STDERR "** PAGE: $article->{id} - cannot create $srcname: $!\n";
  }

  $content;
}

sub _have_group_access {
  my ($req, $user, $group_ids, $membership) = @_;

  if (grep $_ > 0, @$group_ids) {
    $membership->{filled}
      or %$membership = map { $_ => 1 } 'filled', $user->group_ids;
    return 1
      if grep $membership->{$_}, @$group_ids;
  }
  for my $query_id (grep $_ < 0, @$group_ids) {
    require BSE::TB::SiteUserGroups;
    my $group = BSE::TB::SiteUserGroups->getQueryGroup($req->cfg, $query_id)
      or next;
    my $rows = BSE::DB->single->dbh->selectall_arrayref($group->{sql}, { MaxRows=>1 }, $user->{id});
    $rows && @$rows
      and return 1;
  }

  return 0;
}

sub has_access {
  my ($class, $req, $article, $user, $default, $membership) = @_;

  defined $default or $default = 1;
  defined $membership or $membership = {};

  my @group_ids = $article->group_ids;
  if ($article->{inherit_siteuser_rights}
      && $article->{parentid} != -1) {
    if (@group_ids) {
      if (_have_group_access($req, $user, \@group_ids, $membership)) {
	return 1;
      }
      else {
	return $class->has_access($req, $article->parent, $user, 0);
      }
    }
    else {
      # ask parent
      return $class->has_access($req, $article->parent, $user, $default);
    }
  }
  else {
    if (@group_ids) {
      $user ||= $req->siteuser
	or return 0;
      if (_have_group_access($req, $user, \@group_ids, $membership)) {
	return 1;
      }
      else {
	return 0;
      }
    }
    else {
      return $default;
    }
  }
}

1;
