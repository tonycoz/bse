package BSE::Edit::Base;
use strict;

# one day I might put something useful here
sub new {
  my ($class, %parms) = @_;

  $parms{cfg}
    or die "Missing cfg parameter";

  return bless \%parms, $class;
}

sub cfg {
  $_[0]{cfg}
}

sub article_class_id {
  my ($class, $id, $articles, $cfg) = @_;

  return unless defined $id and $id =~ /^\d+$/;

  my $article = $articles->getByPkey($id)
    or return;
  
  return $class->article_class($article, $articles, $cfg);
}

sub article_class {
  my ($class, $article, $articles, $cfg) = @_;

  my $editclass = "BSE::Edit::Article";
  $editclass = $article->{generator};
  $editclass =~ s/^(?:BSE::)?Generate::/BSE::Edit::/;
  my $obj = _get_class($editclass, $cfg);
  if ($obj) {
    $article = $obj->get_article($articles, $article);
  }
  return ($obj, $article);
}

sub _get_class {
  my ($class, $cfg) = @_;

  (my $file = $class . ".pm") =~ s!::!/!g;
  eval {
    require $file;
  };
  if ($@) {
    print STDERR "Loading $class: $@\n";
    return;
  }
  return $class->new(cfg=>$cfg, db=>BSE::DB->single);
}

1;
