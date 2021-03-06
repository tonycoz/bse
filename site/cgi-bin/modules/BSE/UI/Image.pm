package BSE::UI::Image;
use strict;
use BSE::TB::Articles;
use BSE::TB::Images;
use BSE::Util::Tags qw(tag_hash);
use BSE::Util::HTML qw(escape_uri);

our $VERSION = "1.002";

# we don't do anything fancy on dispatch yet, so don't use the 
# dispatch classes
sub dispatch {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  $id && $id =~ /^\d+$/
    or return $class->error($req, "required id parameter not present or invalid");
  my $article = BSE::TB::Articles->getByPkey($id)
    or return $class->error($req, "unknown article id $id");

  my $image;
  
  if (defined(my $imid = $cgi->param('imid'))) {
    $imid =~ /^\d+$/
      or return $class->error($req, "Invalid imid supplied");
    $image = BSE::TB::Images->getByPkey($imid);

    $image && $image->{articleId} == $article->{id}
      or return $class->error($req, "Unknown image identifier supplied");
  }
  elsif (defined(my $imname = $cgi->param('imname'))) {
    length $imname and $imname =~ /^\w+$/
      or return $class->error($req, "Invalid imname supplied");
    ($image) = BSE::TB::Images->getBy(articleId=>$article->{id}, name=>$imname)
      or return $class->error($req, "Unknown image name supplied");
  }

  # check the user has access to the article
  if ($article->is_dynamic && !$req->siteuser_has_access($article)) {
    if ($req->siteuser) {
      return $class->error
	($req, "You do not have access to view this image");
    }
    else {
      my $cfg = $req->cfg;
      my $refresh = "/cgi-bin/image.pl?id=$article->{id}&imid=$image->{id}";
      my $logon =
	$cfg->entry('site', 'url') . "/cgi-bin/user.pl?show_logon=1&r=".escape_uri($refresh)."&m=You+need+to+logon+to+view+this+image";
      return BSE::Template->get_refresh($logon, $cfg);
    }
  }

  $req->set_article(article=>$article);
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     article => [ \&tag_hash, $article ],
     image => [ \&tag_hash, $image ],
    );

  return $req->response('image', \%acts);
}

# returns an error page
sub error {
  my ($class, $req, $msg) = @_;

  require BSE::UI::Dispatch;
  return BSE::UI::Dispatch->error($req, { error => $msg });
}

1;
