package BSE::Util::DynamicTags;
use strict;
use BSE::Util::Tags;
use DevHelp::HTML;

sub tags {
  my ($class, $req) = @_;
  
  return
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     user => [ \&tag_user, $req ],
     ifUser => [ \&tag_ifUser, $req ],
     ifUserCanSee => [ \&tag_ifUserCanSee, $req ],
    );
}

sub tag_ifUser {
  my ($req, $args) = @_;

  my $user = $req->siteuser
    or return '';
  if ($args) {
    return $user->{$args};
  }
  else {
    return 1;
  }
}

sub tag_user {
  my ($req, $args) = @_;

  my $siteuser = $req->siteuser
    or return '';

  exists $siteuser->{$args}
    or return '';

  escape_html($siteuser->{$args});
}

sub tag_ifUserCanSee {
  my ($req, $args) = @_;

  $args 
    or return 0;

  my $article;
  if ($args =~ /^\d+$/) {
    $article = Articles->getByPkey($args);
  }
  else {
    $article = $req->get_article($args);
  }
  $article
    or return 0;

  print STDERR "$args -> $article ($article->{id})\n";

  $req->siteuser_has_access($article);
}

1;
