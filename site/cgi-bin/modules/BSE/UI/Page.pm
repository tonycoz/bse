package BSE::UI::Page;
use strict;
use Articles;
use BSE::Util::HTML qw(escape_uri);
use BSE::UI::Dispatch;
use BSE::Template;
our @ISA = qw(BSE::UI::Dispatch);

our $VERSION = "1.005";

# we don't do anything fancy on dispatch yet, so don't use the 
# dispatch classes
sub dispatch {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $article;
  my $id;
  my $found_by_id = 0;
  my @more_headers;
  my $dump = "";

  my $page = $self->action;
  unless ($page) {
    ($page) = $cgi->param("page");
  }
  unless ($page) {
    ($page) = $cgi->param("alias");
  }
  unless ($page) {
    my $prefix = $cfg->entry('basic', 'alias_prefix', '');

    if ($ENV{REDIRECT_URL} && $ENV{SCRIPT_URL} =~ m(^\Q$prefix\E/)) {
      (my $url = $ENV{SCRIPT_URL}) =~ s(^\Q$prefix\E/)();
      ($page) = $url =~ m(^([a-zA-Z0-9_/-]+))
	or return $self->error($req, "Missing document $ENV{SCRIPT_URL}");
    }
  }
  unless ($page) {
    if ($ENV{PATH_INFO} && $ENV{PATH_INFO} =~ m(^/([A-Za-z0-9_/-]+)$)) {
      $page = $1;
    }
  }

  unless ($page) {
    my $dump = "Environment:\n";
    for my $key (keys %ENV) {
      $dump .= " $key: $ENV{$key}\n";
    }
    $dump .= "\nParam:\n";
    for my $key ($cgi->param) {
      $dump .= "  $key:\n";
      my @values = $cgi->param($key);
      for my $val (@values) {
	if (length($val) > 60) {
	  substr($val, 60) = "...";
	}
	$val =~ s((["']))(\\$1)g;
	$dump .= qq(    "$val"\n);
      }
    }
    $req->audit
      (
       component => "page::param",
       msg => "No page, alias or path specifying a page found",
       level => "error",
       dump => $dump,
      );
    return $self->error($req, "No page or alias specified");
  }

  if ($page) {
    $dump .= "Page lookup: '$page'\n";
    if ($page =~ /^[0-9]+$/) {
      $article = Articles->getByPkey($page)
	or return $self->error($req, "unknown article id $page");
      $found_by_id = 1;
    }
    elsif ($page =~ m(^[a-zA-Z0-9/_-]+$)) {
      my $alias = $page;
      if ($cfg->entry("basic", "alias_suffix", 1)) {
	$alias =~ s((/[0-9a-zA-Z_-]+)$)();
	$dump .= "Stripped title suffix '$1'\n" if defined $1;
      }
      if ($cfg->entry("basic", "alias_recursive") &&
	  $alias =~ m(/([0-9a-zA-Z_-]+)$)) {
	$alias = $1;
	$dump .= "Removed recursive prefix\n";
      }
      $dump .= "Looking for alias: $alias\n";
      ($article) = Articles->getBy(linkAlias => $alias);
    }
  }

  unless ($article) {
    $req->audit
      (
       component => "page::param",
       msg => "No article '$page' found",
       level => "error",
       dump => $dump,
      );
    if ($cfg->entry('debug', 'nopage')) {
      print STDERR "Request to page.pl with no page or alias - ";
      if ($ENV{HTTP_REFERER}) {
	print STDERR "Referer $ENV{HTTP_REFERER}\n";
      }
      else {
	print STDERR "No referer\n";
      }
    }
    return $self->error($req, "Page id or alias specified for display not found");
  }

  unless ($article->should_generate) {
    my $result = $self->error($req, "Sorry, this page is not available");
    push @{$result->{headers}}, "Status: 404";
    return $result;
  }

  if ($found_by_id && 
      $article->linkAlias &&
      $cfg->entry("basic", "redir_to_alias", 0)) {
    # this should be a 301
    return BSE::Template->get_moved($article->link($cfg), $cfg);
  }

  # check if we should override the default no-cache
  my $no_cache_dynamic;
  if ($article->{flags} =~ /A/) {
    $no_cache_dynamic = 1;
  }
  elsif ($article->{flags} =~ /B/) {
    $no_cache_dynamic = 0;
  }
  defined $no_cache_dynamic
    or $no_cache_dynamic = $cfg->entry("template $article->{template}", "no_cache_dynamic");
  defined $no_cache_dynamic
    or $no_cache_dynamic = $req->cfg->entry("article", "no_cache_dynamic");

  $id = $article->{id};

  if (!$article->is_dynamic 
      && ($cfg->entry('basic', 'alias_static_redirect', 1)
	  || $cgi->param('redirect'))) {
    return BSE::Template->get_refresh($article->{link}, $cfg);
  }

  if ($cfg->entry('basic', 'alias_use_static', 1)
      && !$article->is_dynamic
      && -r (my $file = $article->link_to_filename($cfg))) {
    return
      {
       content_filename => $file,
       type => BSE::Template->get_type($cfg, $article->{template}),
       no_cache_dynamic => $no_cache_dynamic,
      };
  }

  # get the dynamic generate for this article type
  my $gen_class = $article->{generator};
  $gen_class =~ s/.*\W//;
  $gen_class = "BSE::Dynamic::".$gen_class;
  (my $gen_file = $gen_class . ".pm") =~ s!::!/!g;
  eval {
    require $gen_file;
  };
  $@ and return $self->error($req, $@);
  my $gen = $gen_class->new($req);
  $article = $gen->get_real_article($article)
    or return $self->error($req, "Cannot get full article for $id");

  $article->is_dynamic
    or print STDERR "** page.pl called for non-dynamic article $id\n";

  unless ($req->siteuser_has_access($article)) {
    if ($req->siteuser) {
      return $self->error
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
    if (open my $src, "< $srcname") {
      local $/;
      if ($cfg->utf8) {
	my $charset = $cfg->charset;
	binmode $src, ":encoding($charset)";
      }
      $template = <$src>;
      close $src;
    }
    else {
      print STDERR "** PAGE: $id - page file exists but isn't readable\n";
    }
  }
  unless (defined $template) {
    $debug_jit && !$dynamic_pregen
      and print STDERR "** JIT: $id - pregen page not found but JIT off\n";

    $template = $self->_generate_pregen($req, $article, $srcname);
  }

  my $result = $gen->generate($article, $template);

  if (@more_headers) {
    push @{$result->{headers}}, @more_headers;
  }

  $result->{no_cache_dynamic} = $no_cache_dynamic;

  return $result;
}

sub _generate_pregen {
  my ($self, $req, $article, $srcname) = @_;

  my $articles = 'Articles';
  my $genname = $article->{generator};
  eval "use $genname";
  $@ && die $@;
  my $gen = $genname->new(articles=>$articles, cfg=>$req->cfg, 
			  top=>$article,
			 dynamic => 1);

  my $content = $gen->generate($article, $articles);

  if (open my $cfile, "> $srcname") {
    binmode $cfile;
    if ($req->cfg->utf8) {
      my $charset = $req->cfg->charset;
      binmode $cfile, ":encoding($charset)";
    }
    print $cfile $content;
    close $cfile;
  }
  else {
    print STDERR "** PAGE: $article->{id} - cannot create $srcname: $!\n";
  }

  return $content;
}

1;
