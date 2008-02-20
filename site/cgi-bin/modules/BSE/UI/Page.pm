package BSE::UI::Page;
use strict;
use Articles;
use DevHelp::HTML qw(escape_uri);
use BSE::UI::Dispatch;
our @ISA = qw(BSE::UI::Dispatch);

# we don't do anything fancy on dispatch yet, so don't use the 
# dispatch classes
sub dispatch {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $article;
  my $id;
    my @more_headers;
  if ($self->action) {
    my $action = $self->action;
    if ($action =~ /^\d+$/) {
      $article = Articles->getByPkey($action)
	or return $self->error($req, "unknown article id $action");
    }
    elsif ($action =~ /^\w+$/) {
      $article = Articles->getBy(linkAlias => $action)
	or return $self->error($req, "Unknown article alias '$action'");
    }
  }
  else {
    $id = $cgi->param('page');
    my $prefix = $cfg->entry('basic', 'alias_prefix', '');
    if ($id) {
      $id && $id =~ /^\d+$/
	or return $self->error($req, "page parameter not valid");
      $article = Articles->getByPkey($id)
	or return $self->error($req, "unknown article id $id");
    }
    elsif (my $alias = $cgi->param('alias')) {
      $article = Articles->getBy(linkAlias => $alias)
	or return $self->error($req, "Unknown article alias '$alias'");
    }
    elsif ($ENV{REDIRECT_URL} && $ENV{SCRIPT_URL} =~ m(^\Q$prefix\E/)) {
      (my $url = $ENV{SCRIPT_URL}) =~ s(^\Q$prefix\E/)();
      my ($alias) = $url =~ /^([a-zA-Z0-9_]+)/
	or return $self->error($req, "Missing document $ENV{SCRIPT_URL}");
      
      $article = Articles->getBy(linkAlias => $alias)
	or return $self->error($req, "Unknown article alias '$alias'");
      
      # have the client treat this as successful, though an error is
      # still written to the Apache error log
      push @more_headers, "Status: 200";
    }
  }
  unless ($article) {
    if ($cfg->entry('debug', 'nopage')) {
      print STDERR "Request to page.pl with no page or alias - ";
      if ($ENV{HTTP_REFERER}) {
	print STDERR "Referer $ENV{HTTP_REFERER}\n";
      }
      else {
	print STDERR "No referer\n";
      }
    }
    return $self->error($req, "No page or page alias specified for display");
  }

  $id = $article->{id};

  if (!$article->is_dynamic 
      && $cfg->entry('basic', 'alias_static_redirect', 1)) {
    require BSE::Template;
    return BSE::Template->get_refresh($article->{link}, $cfg);
  }

  if ($cfg->entry('basic', 'alias_use_static', 1)
      && !$article->is_dynamic
      && -r (my $file = $article->link_to_filename($cfg))) {
    if (open DOC, "< $file") {
      my $content = do { local $/; <DOC> };
      close DOC;
      return
	{
	 content => $content,
	 type => BSE::Template->get_type($cfg, $article->{template})
	};
    }
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
    
    $template = $self->_generate_pregen($req, $article, $srcname);
  }

  my $result = $gen->generate($article, $template);

  if (@more_headers) {
    push @{$result->{headers}}, @more_headers;
  }

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

1;
