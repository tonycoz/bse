package BSE::UI::AdminEdit;
use strict;
use base 'BSE::UI::AdminDispatch';
use BSE::Edit::Base;
use BSE::TB::Articles;

our $VERSION = "1.001";

sub dispatch {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $id = $cgi->param('id');
  my $articles = 'BSE::TB::Articles'; # for a later switch to proper objects, I hope
  my $result;
  if (defined $id && $id =~ /\d/ && $id == -1) {
    my $obj = get_class('BSE::Edit::Site', $cfg)
      or die "Cannot get sections class";
    $result = $obj->edit_sections($req, $articles);
  }
  elsif (my ($obj, $article) = BSE::Edit::Base->article_class_id($id, $articles, $cfg)) {
    $result = $obj->article_dispatch($req, $article, $articles);
  }
  elsif ($id && $req->is_ajax) {
    $result = $req->json_content
      (
       success => 0,
       error_code => "UNKNOWN",
       message => "Unknown article id $id"
      );
  }
  else {
    # look for a type
    my $obj;
    my $type = $cgi->param('type');
    if ($type && $type !~ /\W/) {
      my $class = "BSE::Edit::$type";
      $obj = get_class($class, $cfg);
    }
    unless ($obj) {
      my $parentid = $cgi->param('parentid');
      my $parent;
      if (($obj, $parent) = BSE::Edit::Base->article_class_id($parentid, $articles, $cfg)) {
	if (my ($class) = $obj->child_types($parent)) {
	  $obj = get_class($class, $cfg);
	}
	else {
	  undef $obj;
	}
      }
    }
    unless ($obj) {
      # last try
      $obj = get_class("BSE::Edit::Article", $cfg)
	or die "Cannot get article class!!";
    }
    $result = $obj->noarticle_dispatch($req, $articles);
  }

  return $result;
}

sub get_class {
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
