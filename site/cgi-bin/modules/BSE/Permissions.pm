package BSE::Permissions;
use strict;

sub new {
  my ($class, $cfg) = @_;

  # load global permissions
  my @gobjs;
  my %gobjs;
  my %gvalues = $cfg->entries('global permissions');
  my $maxgid = 0;
  for my $name (keys %gvalues) {
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
    $obj{artinfo} = _make_art_info($obj{permissions});

    push @gobjs, \%obj;
    $gobjs{$name} = \%obj;
  }

  # load article permissions
  my @aobjs;
  my %aobjs;
  my %avalues = $cfg->entries('article permissions');
  my $maxaid = 0;
  for my $name (keys %avalues) {
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

sub can_user {
  my ($self, $user, $article, @actions) = @_;

  
}

sub _make_perm_info {
  my ($perm) = @_;

  my $not = $perm =~ s/^!//;
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
  my ($art) = @_;

  my $not = $art =~ s/^!//;
  my @tests = split /,/, $art;
  my @arts;
  for my $test (@tests) {
    if ($test =~ /^(?:\d+|-1|[a-z]\w+)$/) {
      push @arts, { type=>'exact', article=>$test };
    }
    elsif ($test =~ /^childof\((\d+|-1|[a-z]\w+)\)$/) {
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

1;
