package BSE::Dynamic::Article;
use strict;
use BSE::Util::Tags qw(tag_hash);
use BSE::Template;

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

  return
    (
     dynarticle => [ \&tag_hash, $article ],
     BSE::Util::Tags->basic({}, $self->{req}->cgi, $self->{req}->cfg),
    );
}

sub get_real_article {
  my ($self, $article) = @_;

  return $article;
}

1;
