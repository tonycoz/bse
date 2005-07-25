package BSE::UI::Image;
use strict;
use Articles;
use Images;
use BSE::Util::Tags qw(tag_hash);

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

  my $image;
  
  if (defined(my $imid = $cgi->param('imid'))) {
    $imid =~ /^\d+$/
      or return $class->error($req, "Invalid imid supplied");
    $image = Images->getByPkey($imid);

    $image && $image->{articleId} == $article->{id}
      or return $class->error($req, "Unknown image identifier supplied");
  }
  elsif (defined(my $imname = $cgi->param('imname'))) {
    length $imname and $imname =~ /^\w+$/
      or return $class->error($req, "Invalid imname supplied");
    ($image) = Images->getBy(articleId=>$article->{id}, name=>$imname)
      or return $class->error($req, "Unknown image name supplied");
  }

  my %acts;
  %acts =
    (
     BSE::Util::Tags->static(),
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
