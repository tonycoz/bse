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
  my $allkid_index;
  my $allkid_data;
  return
    (
     $self->SUPER::tags(),
     dynarticle => [ \&tag_hash, $article ],
     ifAncestor => [ tag_ifAncestor => $self, $article ],
     ifStepAncestor => [ tag_ifStepAncestor => $self, $article ],
     $self->dyn_iterator('dynallkids', 'dynallkid', $article,
			 \$allkid_index, \$allkid_data),
     $self->dyn_iterator('dynchildren', 'dynchild', $article),
     $self->dyn_iterator('dynstepparents', 'dynstepparent', $article),
     dynmoveallkid => 
     [ tag_dynmove => $self, \$allkid_index, \$allkid_data, 
       "stepparent=$article->{id}" ],
     url => [ tag_url => $self, $article ],
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

sub tag_dynmove {
  my ($self, $rindex, $rrdata, $url_prefix, $args, $acts, $templater) = @_;

  return '' unless $self->admin_mode;

  return '' unless $$rrdata && @$$rrdata > 1;

  require BSE::Arrows;
  *make_arrows = \&BSE::Arrows::make_arrows;

  my ($img_prefix, $url_add) = 
    DevHelp::Tags->get_parms($args, $acts, $templater);
  defined $img_prefix or $img_prefix = '';
  defined $url_add or $url_add = '';
  my $refresh_to = $ENV{SCRIPT_NAME} . "?id=" . 
    $self->{req}->get_article('dynarticle')->{id} . $url_add;
  my $move = "$Constants::CGI_URI/admin/move.pl?";
  $move .= $url_prefix . '&' if $url_prefix;
  $move .= 'd=swap&id=' . $$$rrdata[$$rindex]{id} . '&';
  my $down_url = '';
  if ($$rindex < $#$$rrdata) {
    $down_url = $move . 'other=' . $$$rrdata[$$rindex+1]{id};
  }
  my $up_url = '';
  if ($$rindex > 0) {
    $up_url = $move . 'other=' . $$$rrdata[$$rindex-1]{id};
  }

  return make_arrows($self->{req}->cfg, $down_url, $up_url, $refresh_to, $img_prefix);
}

sub tag_url {
  my ($self, $top, $name, $acts, $func, $templater) = @_;

  my $item = $self->{admin} ? 'admin' : 'link';
  my $article = $self->{req}->get_article($name)
    or return "** unknown article $name **";

  my $value = $article->{$item};

  if ($top->{$item} =~ /^\w+:/ && $value !~ /^\w+:/) {
    $value = $self->{req}->cfg->entryErr('site', 'url') . $value;
  }
  
  return escape_html($value);
}

sub get_real_article {
  my ($self, $article) = @_;

  return $article;
}

sub admin_mode {
  my ($self) = @_;

  $self->{admin};
}

1;
