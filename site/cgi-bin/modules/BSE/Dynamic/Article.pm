package BSE::Dynamic::Article;
use strict;
use BSE::Util::Tags qw(tag_hash);
use BSE::Template;
use DevHelp::HTML;

sub new {
  my ($class, $req) = @_;

  return bless { req=> $req }, $class;
}

sub generate {
  my ($self, $article, $template) = @_;

  my %acts = $self->tags($article);

  my $result =
    {
     content => BSE::Template->replace($template, $self->{req}->cfg, \%acts),
     type => BSE::Template->get_type($self->{req}->cfg, $article->{template}),
    };

  my @headers = "Content-Length: ".length $result->{content};
  $result->{headers} = \@headers;

  return $result;
}

sub tags {
  my ($self, $article) = @_;
  
  $self->{req}->set_article(dynarticle => $article);
  return
    (
     dynarticle => [ \&tag_hash, $article ],
     $self->{req}->dyn_user_tags(),
    );
}

sub get_real_article {
  my ($self, $article) = @_;

  return $article;
}

1;
