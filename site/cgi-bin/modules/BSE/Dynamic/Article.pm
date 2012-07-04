package BSE::Dynamic::Article;
use strict;
use BSE::Util::Tags qw(tag_article);
use BSE::Template;
use BSE::Util::HTML;
use base qw(BSE::Util::DynamicTags);

our $VERSION = "1.005";

sub new {
  my ($class, $req, %opts) = @_;

  my $self = $class->SUPER::new($req, %opts);

  $self->{admin} = 0;
  $self->{admin_links} = 0;
  ++$self->{admin} if $opts{admin};
  ++$self->{admin_links} if $opts{admin_links};

  return $self;
}

sub generate {
  my ($self, $article, $template) = @_;

  $self->{article} = $article;
  my %acts;
  if ($self->{admin}) {
    %acts = ( $self->tags($article), BSE::Util::Tags->secure($self->{req}) );
  }
  else {
    %acts = $self->tags($article);
  }

  require BSE::Variables;
  $self->{req}->set_variable
    (
     bse =>
     BSE::Variables->dyn_variables
     (
      request => $self->req,
      admin => $self->{admin},
      admin_links => $self->{admin_links},
     ),
    );

  # FIXME: this should be done through the request object
  $self->{req}->_set_vars();
  my $result =
    {
     content => BSE::Template->replace($template, $self->{req}->cfg, \%acts, $self->{req}->{vars}),
     type => BSE::Template->get_type($self->{req}->cfg, $article->{template}),
    };

  if (BSE::Cfg->utf8) {
    require Encode;
    $result->{content} = Encode::encode(BSE::Cfg->charset, $result->{content});
  }

  %acts = (); # hopefully break circular refs

  my @headers = "Content-Length: ".length $result->{content};
  $result->{headers} = \@headers;

  return $result;
}

sub article {
  $_[0]{article};
}

sub tags {
  my ($self, $article) = @_;
  
  $self->{req}->set_article(dynarticle => $article);
  my $allkid_index;
  my $allkid_data;
  my $section; # managed by tag_dynsection
  my $message;
  return
    (
     $self->SUPER::tags(),
     dynarticle => [ \&tag_article, $article, $self->{req}->cfg ],
     dynsection => [ tag_dynsection => $self, $article, \$section ],
     ifAncestor => [ tag_ifAncestor => $self, $article ],
     ifStepAncestor => [ tag_ifStepAncestor => $self, $article ],
     $self->dyn_article_iterator('dynallkids', 'dynallkid', $article,
			 \$allkid_index, \$allkid_data),
     $self->dyn_article_iterator('dynchildren', 'dynchild', $article),
     $self->dyn_article_iterator('dynstepparents', 'dynstepparent', $article),
     dynmoveallkid => 
     [ tag_dynmove => $self, \$allkid_index, \$allkid_data, 
       "stepparent=$article->{id}" ],
     url => [ tag_url => $self, $article ],
     message => [ tag_message => $self, \$message ],
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

sub tag_ifStepAncestor {
  my ($self, $article, $arg) = @_;

  unless ($arg =~ /^\d+$/) {
    my $art = $self->{req}->get_article($arg)
      or return 0;
    $arg = $art->{id};
  }

  return 1 if $article->{id} == $arg;

  return $article->is_step_ancestor($arg);
}

sub tag_url {
  my ($self, $top, $name, $acts, $func, $templater) = @_;

  my $article = $self->{req}->get_article($name)
    or return "** unknown article $name **";

  my $value;
  my $top_link;
  if ($self->{admin_links}) {
    $value = $article->{admin};
    if (!$self->{admin}) {
      $value .= $value =~ /\?/ ? "&" : "?";
      $value .= "admin=0&admin_links=1";
    }

    $top_link = $top->{admin};
  }
  else {
    $value = $article->link($self->{req}->cfg);

    $top_link = $top->{link};
  }

  if ($top_link =~ /^\w+:/ && $value !~ /^\w+:/) {
    $value = $self->{req}->cfg->entryErr('site', 'url') . $value;
  }
  
  return escape_html($value);
}

=item dynsection I<field>

Retrieve a value from the section the article is in.

=cut

sub tag_dynsection {
  my ($self, $article, $rsection, $args) = @_;

  unless ($$rsection) {
    $$rsection = $article->section;
  }

  return tag_article($$rsection, $self->{req}->cfg, $args);
}

=item message

Returns any saved message content.

=cut

sub tag_message {
  my ($self, $rmessage) = @_;

  unless (defined $$rmessage) {
    $$rmessage = $self->{req}->message;
  }

  return $$rmessage;
}

sub get_real_article {
  my ($self, $article) = @_;

  return $article;
}

sub admin_mode {
  my ($self) = @_;

  $self->{admin};
}

sub _find_articles {
  my ($self, $article_id) = @_;

  my $article = $self->{req}->get_article('dynarticle');
  if ($article_id eq 'children') {
    return $article->all_visible_kids;
  }
  elsif ($article_id eq 'parent') {
    my $parent = $article->parent;
    $parent
      and return $parent;
  }

  return $self->SUPER::_find_articles($article_id);
}

1;
