package BSE::Util::DynamicTags;
use strict;
use BSE::Util::Tags;
use DevHelp::HTML;

sub new {
  my ($class, $req) = @_;
  return bless { req => $req }, $class;
}

sub tags {
  my ($self) = @_;
  
  my $req = $self->{req};
  return
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     user => [ \&tag_user, $req ],
     ifUser => [ \&tag_ifUser, $req ],
     ifUserCanSee => [ \&tag_ifUserCanSee, $req ],
     $self->dyn_iterator('dynlevel1s', 'dynlevel1'),
     $self->dyn_iterator('dynlevel2s', 'dynlevel2'),
     $self->dyn_iterator('dynlevel3s', 'dynlevel3'),
     $self->dyn_iterator('dynallkids_of', 'dynofallkid'),
     $self->dyn_iterator('dynchildren_of', 'dynofchild'),
     url => [ tag_url => $self ],
     ifAncestor => 0,
     ifUserMemberOf => [ tag_ifUserMemberOf => $self ],
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
    require Articles;
    $article = Articles->getByPkey($args);
  }
  else {
    $article = $req->get_article($args);
  }
  $article
    or return 0;

  $req->cfg->entry('basic', 'admin_sees_all', 1)
    and return 1;

  $req->siteuser_has_access($article);
}

sub tag_ifUserMemberOf {
  my ($self, $args, $acts, $func, $templater) = @_;

  my $req = $self->{req};

  my $user = $req->siteuser
    or return 0; # no user, no group

  my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater);

  $name
    or return 0; # no group name
  
  require BSE::TB::SiteUserGroups;
  my $group = BSE::TB::SiteUserGroups->getByName($req->cfg, $name);
  unless ($group) {
    print STDERR "Unknown group name '$name' in ifUserMemberOf\n";
    return 0;
  }

  return $group->contains_user($user);
}

sub tag_url {
  my ($self, $name, $acts, $func, $templater) = @_;

  my $item = $self->{admin} ? 'admin' : 'link';
  my $article = $self->{req}->get_article($name)
    or return "** unknown article $name **";
  return escape_html($article->{$item});
}

sub iter_dynlevel1s {
  my ($self, $unused, $args) = @_;

  my $result = $self->get_cached('dynlevel1');
  $result
    and return $result;

  require Articles;
  $result = $self->access_filter(Articles->listedChildren(-1));
  $self->set_cached(dynlevel1 => $result);

  return $result;
}

sub iter_dynlevel2s {
  my ($self, $unused, $args) = @_;

  my $req = $self->{req};
  my $parent = $req->get_article('dynlevel1')
    or return [];

  my $cached = $self->get_cached('dynlevel2');
  $cached && $cached->[0] == $parent->{id}
    and return $cached->[1];

  require Articles;
  my $result = $self->access_filter(Articles->listedChildren($parent->{id}));
  $self->set_cached(dynlevel2 => [ $parent->{id}, $result ]);

  return $result;
}

sub iter_dynlevel3s {
  my ($self, $unused, $args) = @_;

  my $req = $self->{req};
  my $parent = $req->get_article('dynlevel2')
    or return [];

  my $cached = $self->get_cached('dynlevel3');
  $cached && $cached->[0] == $parent->{id}
    and return $cached->[1];

  require Articles;
  my $result = $self->access_filter( Articles->listedChildren($parent->{id}));
  $self->set_cached(dynlevel3 => [ $parent->{id}, $result ]);

  return $result;
}

sub iter_dynallkids_of {
  my ($self, $unused, $args, $acts, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $self->{req}->get_article($id);
    }
  }
  @ids = grep defined && /^\d+$|^-1$/, @ids;

  require Articles;
  return $self->access_filter(map Articles->all_visible_kids($_), @ids);
}

sub iter_dynchildren_of {
  my ($self, $unused, $args, $acts, $templater) = @_;

  my @ids = map { split } DevHelp::Tags->get_parms($args, $acts, $templater);
  for my $id (@ids) {
    unless ($id =~ /^\d+$|^-1$/) {
      $id = $self->{req}->get_article($id);
    }
  }
  @ids = grep defined && /^\d+$|^-1$/, @ids;

  require Articles;
  return $self->access_filter( map Articles->listedChildren($_), @ids);
}

sub access_filter {
  my ($self, @articles) = @_;

  my $req = $self->{req};

  my $admin_sees_all = $req->cfg->entry('basic', 'admin_sees_all', 1);

  $admin_sees_all && $self->{admin} and 
    return \@articles;

  return [ grep $req->siteuser_has_access($_), @articles ];
}

sub _dyn_iterate_reset {
  my ($self, $rdata, $rindex, $plural, $context, $args, $acts, $name, 
      $templater) = @_;

  my $method = "iter_$plural";
  $$rdata = $self->$method($context, $args, $acts, $templater);
  $$rindex = -1;

  1;
}

sub _dyn_iterate {
  my ($self, $rdata, $rindex, $single) = @_;

  if (++$$rindex < @$$rdata) {
    $self->{req}->set_article($single => $$rdata->[$$rindex]);
    return 1;
  }
  else {
    $self->{req}->set_article($single => undef);
    return;
  }
}

sub _dyn_item {
  my ($self, $rdata, $rindex, $single, $plural, $args) = @_;

  if ($$rindex < 0 || $$rindex >= @$$rdata) {
    return "** $single only usable inside iterator $plural **";
  }

  my $item = $$rdata->[$$rindex]
    or return '';
  my $value = $item->{$args};
  defined $value 
    or return '';

  return escape_html($value);
}

sub _dyn_index {
  my ($self, $rindex, $rdata, $single) = @_;

  if ($$rindex < 0 || $$rindex >= @$$rdata) {
    return "** $single only valid inside iterator **";
  }

  return $$rindex;
}

sub _dyn_number {
  my ($self, $rindex, $rdata, $single) = @_;

  if ($$rindex < 0 || $$rindex >= @$$rdata) {
    return "** $single only valid inside iterator **";
  }

  return 1 + $$rindex;
}

sub _dyn_count {
  my ($self, $rdata, $rindex, $plural, $context, $args, $acts, $name, 
      $templater) = @_;

  my $method = "iter_$plural";
  my $data = $self->$method($context, $args, $acts, $templater);

  return scalar @$data;
}

sub _dyn_if_first {
  my ($self, $rindex, $rdata) = @_;

  $$rindex == 0;
}

sub _dyn_if_last {
  my ($self, $rindex, $rdata) = @_;

  $$rindex == $#$$rdata;
}

sub dyn_iterator {
  my ($self, $plural, $single, $context, $rindex, $rdata) = @_;

  my $method = $plural;
  my $index;
  defined $rindex or $rindex = \$index;
  my $data;
  defined $rdata or $rdata = \$data;
  return
    (
     "iterate_${plural}_reset" =>
     [ _dyn_iterate_reset => $self, $rdata, $rindex, $plural, $context ],
     "iterate_$plural" =>
     [ _dyn_iterate => $self, $rdata, $rindex, $single, $context ],
     $single => 
     [ _dyn_item => $self, $rdata, $rindex, $single, $plural ],
     "${single}_index" =>
     [ _dyn_index => $self, $rindex, $rdata, $single ],
     "${single}_number" =>
     [ _dyn_number => $self, $rindex, $rdata ],
     "${single}_count" =>
     [ _dyn_count => $self, $rindex, $rdata, $plural, $context ],
     "if\u$plural" =>
     [ _dyn_count => $self, $rindex, $rdata, $plural, $context ],
     "ifLast\u$single" => [ _dyn_if_last => $self, $rindex, $rdata ],
     "ifFirst\u$single" => [ _dyn_if_first => $self, $rindex, $rdata ],
    );
}

sub get_cached {
  my ($self, $id) = @_;

  return $self->{_cache}{$id};
}

sub set_cached {
  my ($self, $id, $value) = @_;

  $self->{_cache}{$id} = $value;
}

1;
