package BSE::Dynamic::Article;
use strict;
use BSE::Util::Tags qw(tag_hash);
use BSE::Template;
use DevHelp::HTML;
use base qw(BSE::Util::DynamicTags);

sub new {
  my ($class, $req, %opts) = @_;

  my $self = $class->SUPER::new($req, %opts);

  ++$self->{admin} if $opts{admin};

  return $self;
}

sub generate {
  my ($self, $article, $template) = @_;

  my %acts = $self->tags($article);

  my $result =
    {
     content => BSE::Template->replace($template, $self->{req}->cfg, \%acts),
     type => BSE::Template->get_type($self->{req}->cfg, $article->{template}),
    };

  %acts = (); # hopefully break circular refs

  my @headers = "Content-Length: ".length $result->{content};
  $result->{headers} = \@headers;

  return $result;
}

sub tags {
  my ($self, $article) = @_;
  
  $self->{req}->set_article(dynarticle => $article);
  return
    (
     $self->SUPER::tags(),
     dynarticle => [ \&tag_hash, $article ],
     ifAncestor => [ tag_ifAncestor => $self, $article ],
     $self->dyn_iterator('dynallkids', 'dynallkid', $article),
     $self->dyn_iterator('dynchildren', 'dynchild', $article),
     $self->dyn_iterator('dynstepparents', 'dynstepparent', $article),
    );
}

sub iter_dynallkids {
  my ($self, $article, $args) = @_;

  my $result = $self->get_cached('dynallkids');
  $result
    and return $result;
  $result = $self->access_filter($article->all_visible_kids);
  $self->set_cached(dynallkids => $result);

  return $result;
}

sub iter_dynchildren {
  my ($self, $article, $args) = @_;

  my $result = $self->get_cached('dynchildren');
  $result
    and return $result;

  $result = $self->access_filter(Articles->listedChildren($article->{id}));
  $self->set_cached(dynchildren => $result);

  return $result;
}

sub iter_dynstepparents {
  my ($self, $article, $args) = @_;

  my $result = $self->get_cached('dynstepparents');
  $result
    and return $result;

  $result = $self->access_filter($article->visible_step_parents);
  $self->set_cached(dynstepparents => $result);

  return $result;
}

sub tag_ifAncestor {
  my ($self, $article, $arg) = @_;

  unless ($arg =~ /^\d+$/) {
    my $art = $self->{req}->get_article($arg)
      or return 0;
    $arg = $art->{id};
  }

  return 1 if $article->{id} == $arg;

  while ($article->{parentid} != -1) {
    $article->{parentid} == $arg
      and return 1;

    $article = $article->parent;
  }

  return 0;
}

sub get_real_article {
  my ($self, $article) = @_;

  return $article;
}

1;
