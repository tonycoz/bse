package BSE::Permissions;
use strict;

# these are the permissions that are checked beyond just whether the permissions DB allows them
my @checks =
  qw(
     edit_delete_article
     edit_field_edit_title
     edit_field_edit_summary
     edit_add_child
     );
my %checks = map { $_=> 1 } @checks;  

sub new {
  my ($class, $cfg) = @_;

  # load global permissions
  my @gobjs;
  my %gobjs;
  my %gvalues = $cfg->entries('global permissions');
  my $maxgid = 0;
  for my $name (sort keys %gvalues) {
    my $id = $gvalues{$name};
    if ($id > 250) {
      print STDERR "permission id for $name out of range\n";
      next;
    }
    $id > $maxgid and $maxgid = $id;
    my %obj = ( name => $name, id => $id );
    my $section = "permission $name";
    $obj{help} = $cfg->entry($section, 'help', '');
    $obj{descendants} = $cfg->entry($section, 'descendants', 0);
    $obj{brief} = $cfg->entry($section, 'brief', $name);
    $obj{permissions} = $cfg->entry($section, 'permissions')
      or next; # ignore it
    $obj{articles} = $cfg->entry($section, 'articles')
      or next;
    $obj{perminfo} = _make_perm_info($obj{permissions});
    $obj{artinfo} = _make_art_info($obj{articles}, $cfg);

    push @gobjs, \%obj;
    $gobjs{$name} = \%obj;
  }

  # load article permissions
  my @aobjs;
  my %aobjs;
  my %avalues = $cfg->entries('article permissions');
  my $maxaid = 0;
  for my $name (sort keys %avalues) {
    my $id = $avalues{$name};
    if ($id > 250) {
      print STDERR "permission id for $name out of range\n";
      next;
    }
    $id > $maxaid and $maxaid = $id;
    my %obj = ( name => $name, id => $id );
    my $section = "permission $name";
    $obj{help} = $cfg->entry($section, 'help', '');
    $obj{descendants} = $cfg->entry($section, 'descendants', 0);
    $obj{brief} = $cfg->entry($section, 'brief', $name);
    $obj{permissions} = $cfg->entry($section, 'permissions')
      or next; # ignore it
    $obj{perminfo} = _make_perm_info($obj{permissions});

    push @aobjs, \%obj;
    $aobjs{$name} = \%obj;
  }

  return bless {
		gobj_array => \@gobjs,
		gobj_hash  => \%gobjs,
		max_gid    => $maxgid,
		aobj_array => \@aobjs,
		aobj_hash  => \%aobjs,
		max_aid    => $maxaid,
		cfg        => $cfg,
	       }, $class;
}

# check that the user is logged on, assuming we're configured to 
# require that
sub check_logon {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
  $cfg->entry('basic', 'access_control', 0)
    or return 1;

  return 1 if $req->user;

  my $server_auth_admin = $cfg->entry('basic', 'server_auth', 0);

  my $user;
  require BSE::TB::AdminUsers;
  if ($server_auth_admin && $ENV{REMOTE_USER}) {
    ($user) = BSE::TB::AdminUsers->getBy(logon => $ENV{REMOTE_USER});
  }
  if ($req->session->{adminuserid}) {
    $user = BSE::TB::AdminUsers->getByPkey($req->session->{adminuserid});
  }
  if ($user) {
    $req->setuser($user);
    return 1;
  }
  else {
    return 0;
  }
}

sub global_perms {
  my ($self) = @_;

  return @{$self->{gobj_array}};
}

sub max_global_perm_id {
  my ($self) = @_;

  return $self->{max_gid};
}

sub article_perms {
  my ($self) = @_;

  return @{$self->{aobj_array}};
}

sub max_article_perm_id {
  my ($self) = @_;

  return $self->{max_aid};
}

sub get_article_perm {
  my ($self, $artid, $object) = @_;

  my ($result) = BSE::DB->query(articleObjectPerm => $artid, $object->{id});

  return $result;
}

sub set_article_perm {
  my ($self, $artid, $object, $perm_map) = @_;

  my $perm = $self->get_article_perm($artid, $object);
  if ($perm) {
    BSE::DB->run(replaceArticleObjectPerm =>$artid, $object->{id},
		 $perm_map);
  }
  else {
    BSE::DB->run(addArticleObjectPerm =>$artid, $object->{id}, $perm_map);
  }
}

sub _load_user_perms {
  my ($self, $user) = @_;

  require BSE::TB::AdminGroups;
  my @usergroups = BSE::TB::AdminGroups->getSpecial(userPermissionGroups=>$user->{id});
  my @userperms = 
    ( 
     BSE::DB->query(userPerms=>$user->{id}),
     BSE::DB->query(groupPerms=>$user->{id}),
     BSE::DB->query('commonPerms'),
    );
  $self->{usergroups} = \@usergroups;
  $self->{userperms} = \@userperms;

  $self->{userid} = $user->{id};
}

sub _permname_match {
  my ($name, $info) = @_;

  my $match = 0;
  for my $re (@{$info->{res}}) {
    if ($name =~ $re) {
      ++$match;
      last;
    }
  }

  return $info->{not} ? !$match : $match;
}

sub _get_article {
  my ($self, $id) = @_;

  return $self->{artcache}{$id}
    if exists $self->{artcache}{$id};

  if ($id == -1) {
    $self->{sitearticle} ||=
      {
       generator=>'Generate::Article',
       id=>-1,
       parentid=>0,
       title=>'The site',
       level => 0,
      };
    return $self->{sitearticle};
  }
  else {
    require Articles;
    $self->{artcache}{$id} = Articles->getByPkey($id);
  }
}

sub _art_ancestors {
  my ($self, $article) = @_;

  my @result;
  while ($article->{id} && $article->{id} > 0 && $article->{parentid} != -1) {
    $article = $self->_get_article($article->{parentid});
    push @result, $article;
  }
  if ($article && $article->{parentid} == -1) {
    $self->{sitearticle} ||=
      {
       generator=>'Generate::Article',
       id=>-1,
       parentid=>0,
       title=>'The site',
      };
    push @result, $self->{sitearticle};
  }

  @result;
}

sub _garticle_match {
  my ($self, $article, $perm) = @_;

  my @articles = $article;
  if ($perm->{descendants}) {
    push @articles, $self->_art_ancestors($article);
  }

  for my $test (@{$perm->{artinfo}{arts}}) {
    if ($test->{type} eq 'exact') {
      return !$perm->{artinfo}{not}
	if grep $_->{id} == $test->{article}, @articles;
    }
    elsif ($test->{type} eq 'childof') {
      return !$perm->{artinfo}{not}
	if grep $_->{parentid} == $test->{article}, @articles;
    }
    elsif ($test->{type} eq 'typeof') {
      return !$perm->{artinfo}{not}
	if grep $_->{generator} eq "Generate::$test->{name}", @articles;
    }
  }

  return $perm->{artinfo}{not};
}

sub _aarticle_match {
  my ($self, $article, $perm, $id) = @_;

  my @articles = $article;
  if ($perm->{descendants}) {
    push @articles, $self->_art_ancestors($article);
  }
  return 1
    if grep $_->{id} == $id, @articles;

  return 0;
}

sub user_has_perm {
  my ($self, $user, $article, $action, $rmsg) = @_;

  unless ($rmsg) {
    my $msg;
    $rmsg = \$msg;
  }

  unless (ref $article) {
    $article = $self->_get_article($article)
      or return;
  }

  if ($checks{$action}) {
    my $method = "check_$action";
    $self->$method($user, $article, $action, $rmsg)
      or return;
  }

  unless ($self->{cfg}->entry('basic', 'access_control', 0))  {
    return 1;
  }
  
  $self->{userid} && $self->{userid} == $user->{id}
    or $self->_load_user_perms($user);

  for my $permmap ($user->{perm_map}, 
		map $_->{perm_map}, @{$self->{usergroups}}) {
    for my $globperm (@{$self->{gobj_array}}) {
      next
	unless length($permmap) > $globperm->{id}
	  and substr($permmap, $globperm->{id}, 1);
      _permname_match($action, $globperm->{perminfo})
	or next;
      $self->_garticle_match($article, $globperm)
	and return 1;
    }
  }
  for my $perm (@{$self->{userperms}}) {
    for my $artperm (@{$self->{aobj_array}}) {
      next
	unless length($perm->{perm_map}) > $artperm->{id}
	  and substr($perm->{perm_map}, $artperm->{id}, 1);
      _permname_match($action, $artperm->{perminfo})
	or next;
      $self->_aarticle_match($article, $artperm, $perm->{object_id})
	and return 1;
    }
  }

  # we want to switch to making all standard permissions bse_...
  # so allow checks for those
  if ($action =~ /^bse_(\w+)$/) {
    return $self->user_has_perm($user, $article, $1, $rmsg);
  }

  return;
}

sub _make_perm_info {
  my ($perm) = @_;

  my $not = $perm =~ s/^not\((.*)\)$/$1/;
  my @tests = split /,/, $perm;
  my @res;
  for my $test (@tests) {
    (my $re = $test) =~ s/\*/.*/;
    $re = "^$re\$";
    eval {
      $re = qr/$re/;
    };
    if ($@) {
      print STDERR "Bad permission test '$test'\n";
    }
    else {
      push @res, $re;
    }
  }

  return { not=>$not, res=>\@res };
}

sub _make_art_info {
  my ($art, $cfg) = @_;

  my $not = $art =~ s/^not\((.*)\)$/$1/;
  my @tests = split /,/, $art;
  my @arts;
  for my $test (@tests) {
    if ($test =~ /^(?:\d+|-1|[a-z]\w+)$/) {
      unless ($test =~ /^(\d+|-1)$/) {
	my $id = $cfg->entry('articles', $test);
	unless ($id) {
	  print STDERR "Unknown article name '$test' skipped\n";
	  next;
	}
	$test = $id;
      }
      push @arts, { type=>'exact', article=>$test };
    }
    elsif ($test =~ /^childof\((\d+|-1|[a-z]\w+)\)$/) {
      my $name = $1;
      unless ($name =~ /^(\d+|-1)$/) {
	my $id = $cfg->entry('articles', $name);
	unless ($id) {
	  print STDERR "Unknown article name '$name' skipped\n";
	  next;
	}
	$test = $id;
      }
      push @arts, { type=>'childof', article=>$1 };
    }
    elsif ($test =~ /^typeof\((\w+)\)$/) {
      push @arts, { type=>'typeof', name=>$1 };
    }
    else {
      print STDERR "Unrecognized article match '$test'\n";
    }
  }

  return { not=>$not, arts=>\@arts };
}

sub _is_product_and_in_use {
  my ($article) = @_;

  if ($article->{generator} eq 'Generate::Product') {
    # can't delete products that have been used in orders
    require BSE::TB::OrderItems;
    my @items = BSE::TB::OrderItems->getBy(productId=>$article->{id});
    if (@items) {
      return 1;
    }
  }
  return 0;
}

sub check_edit_delete_article {
  my ($self, $user, $article, $action, $rmsg) = @_;

  # can't delete an article that has children
  if (Articles->children($article->{id})) {
    $$rmsg = "This article has children.  You must delete the children first (or change their parents)";
    return;
  }
  if (grep $_ == $article->{id}, @Constants::NO_DELETE) {
    $$rmsg = "Sorry, these pages are essential to the site structure - they cannot be deleted";
    return;
  }
  my $shopid = $self->{cfg}->entryErr('articles', 'shop');
  if ($article->{id} == $shopid) {
    $$rmsg = "Sorry, these pages are essential to the store - they cannot be deleted - you may want to hide the the store instead.";
    return;
  }
  if (_is_product_and_in_use($article)) {
    $$rmsg = "There are orders for this product.  It cannot be deleted.";
    return;
  }

  return 1;
}

sub check_edit_field_edit_title {
  my ($self, $user, $article, $action, $rmsg) = @_;

  if (_is_product_and_in_use($article)) {
    $$rmsg = "There are orders for this product.  The title cannot be changed.";
    return;
  }

  return 1;
}

sub check_edit_field_edit_summary {
  my ($self, $user, $article, $action, $rmsg) = @_;
  
  if (_is_product_and_in_use($article)) {
    $$rmsg = "There are orders for this product.  The summary cannot be changed.";
    return;
  }

  return 1;
}

sub check_edit_add_child {
  my ($self, $user, $article, $action, $rmsg) = @_;

  if ($article->{generator} eq 'Generate::Product') {
    $$rmsg = "Products cannot have children";
    return;
  }
  unless (defined $self->{cfg}->entry('level names', $article->{level}+1)) {
    $$rmsg = "Too many levels";
    return;
  }

  return 1;
}

1;
