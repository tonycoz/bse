package BSE::AdminUsers;
use strict;
use BSE::Util::Tags qw/tag_error_img/;
use BSE::Permissions;
use DevHelp::HTML;
use BSE::CfgInfo qw(admin_base_url);

my %actions =
  (
   users=>1,
   showuser=>1,
   showuserart=>1,
   saveuser=>1,
   saveuserart=>1,
   adduserform => 1,
   adduser=>1,
   groups=>1,
   showgroupart=>1,
   showgroup=>1,
   savegroup=>1,
   savegroupart=>1,
   showobjectart=>1,
   addgroupform=>1,
   addgroup=>1,
   deluser=>1,
   delgroup=>1,
  );

sub dispatch {
  my ($class, $req) = @_;

  BSE::Permissions->check_logon($req)
    or return BSE::Template->get_refresh($req->url('logon'), $req->cfg);

  my $cgi = $req->cgi;
  my $action;
  for my $check (keys %actions) {
    if ($cgi->param("a_$check")) {
      $action = $check;
      last;
    }
  }
  $action ||= 'users';
  my $method = "req_$action";
  $class->$method($req);
}

sub iter_get_users {
  my ($req) = @_;

  require BSE::TB::AdminUsers;
  return BSE::TB::AdminUsers->all;
}

sub iter_get_groups {
  my ($req) = @_;

  require BSE::TB::AdminGroups;
  return BSE::TB::AdminGroups->all;
}

sub iter_get_user_groups {
  my ($req, $args, $acts, $funcname, $templater) = @_;

  my $id = $templater->perform($acts, $args, 'id')
    or return;

  return BSE::DB->query(adminUsersGroups => $id);
}

sub iter_get_group_users {
  my ($req, $args, $acts, $funcname, $templater) = @_;

  my $id = $templater->perform($acts, $args, 'id')
    or return;

  return BSE::DB->query(adminGroupsUsers => $id);
}

my @saltchars = ('.', '/', 0..9, 'A'..'Z', 'a'..'z');

sub _save_htusers {
  my ($class, $req, $rmsg) = @_;

  my $cfg = $req->cfg;

  my $userfile = $cfg->entry('basic', 'htusers')
    or return 1;

  my @users = BSE::TB::AdminUsers->all;
  unless (@users) {
    $$rmsg = "No users to load into $userfile file";
    return;
  }

  my $work = $userfile . ".tmp";
  unless (open USERS, "> $work") {
    $$rmsg = "Cannot create work userfile $work: $!";
    return;
  }
  for my $user (@users) {
    my $salt = join '', @saltchars[rand(@saltchars), rand(@saltchars)];
    my $cryptpw = crypt $user->{password}, $salt;
    print USERS "$user->{logon}:$cryptpw\n";
  }
  close USERS;
  chmod 0644, $work;
  unless (rename $work, $userfile) {
    $$rmsg = "Could not rename $work to $userfile: $!";
    return;
  }

  return 1;
}

sub common_tags {
  my ($class, $req, $msg, $errors) = @_;

  $errors ||= +{};
  $msg ||= $req->cgi->param('m');
  if ($msg) {
    $msg = escape_html($msg);
  }
  else {
    if (values %$errors) {
      $msg = "<p>".join("<br />", map escape_html($_),grep $_, values %$errors)."</p>";
    }
    else {
      $msg = '';
    }
  }
  my @users;
  my $user_index;
  my @groups;
  my $group_index;
  return
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     BSE::Util::Tags->admin(undef, $req->cfg),
     message => $msg,
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_users, $req ], 'iuser', 'users', \@users, \$user_index),
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_groups, $req ], 'igroup', 'groups', \@groups, 
      \$group_index),
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_user_groups, $req, ], 'user_group', 'user_groups'),
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_group_users, $req, ], 'group_user', 'group_users'),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );
}

sub req_users {
  my ($class, $req, $msg, $errors) = @_;

  my %acts;
  %acts = $class->common_tags($req, $msg, $errors);
  return BSE::Template->get_response('admin/userlist', $req->cfg, \%acts);
}

sub req_adduserform {
  my ($class, $req, $msg, $errors) = @_;

  $req->user_can('admin_user_add')
    or return $class->req_users($req, "You don't have admin_user_add access");

  my %acts;
  %acts = $class->common_tags($req, $msg, $errors);
  return BSE::Template->get_response('admin/adduser', $req->cfg, \%acts);
}

sub req_groups {
  my ($class, $req, $msg, $errors) = @_;

  my %acts;
  %acts = $class->common_tags($req, $msg, $errors);

  return BSE::Template->get_response('admin/grouplist', $req->cfg, \%acts);
}

sub req_addgroupform {
  my ($class, $req, $msg, $errors) = @_;

  my %acts;
  %acts = $class->common_tags($req, $msg, $errors);

  return BSE::Template->get_response('admin/addgroup', $req->cfg, \%acts);
}

sub refresh {
  my ($class, $req, $target, @parms) = @_;

  my $url = $req->cgi->param('r');
  unless ($url) {
    $url = admin_base_url($req->cfg);
    $url .= $ENV{SCRIPT_NAME};
    $url .= "?$target=1";
    while (my ($key, $value) = splice @parms, 0, 2) {
      $url .= "&$key=".escape_uri($value);
    }
  }
  
  return BSE::Template->get_refresh($url, $req->cfg);
}

sub hash_tag {
  my ($hash, $args) = @_;

  my $value = $hash->{$args};
  defined $value or $value = '';
  escape_html($value);
}

sub req_adduser {
  my ($class, $req) = @_;

  $req->user_can('admin_user_add')
    or return $class->req_users($req, "You don't have admin_user_add access");

  my $cgi = $req->cgi;
  my $logon = $cgi->param('logon');
  my $name = $cgi->param('name');
  my $password = $cgi->param('password');
  my $confirm = $cgi->param('confirm');
  my %errors;

  defined $logon && length $logon
    or $errors{logon} = 'No logon supplied';
  $name = '' unless defined $name;
  if (defined $password && length $password) {
    if (defined $confirm && length $confirm) {
      $password eq $confirm
	or $errors{confirm} = 'Password is different to confirmation password';
    }
    else {
      $errors{confirm} = 'No confirmation password supplied';
    }
  }
  else {
    $errors{password} = 'No password supplied';
    defined $confirm && length $confirm
      or $errors{confirm} = 'No confirmation password supplied';
  }

  keys %errors
    and return $class->req_adduserform($req, undef, \%errors);

  require BSE::TB::AdminUsers;
  my $old = BSE::TB::AdminUsers->getBy(logon=>$logon)
    and return $class->req_adduserform($req, "Logon '$logon' already exists");
  my %user =
    (
     type => 'u',
     logon => $logon,
     name => $name, 
     password => $password,
     perm_map => '',
    );
  my @cols = BSE::TB::AdminUser->columns;
  shift @cols;
  my $user = BSE::TB::AdminUsers->add(@user{@cols});

  my $msg = "User $logon created";

  $class->_save_htusers($req, \$msg);

  return $class->refresh($req, 'a_showuser', userid=>$user->{id},
			 'm'=>$msg);
}

sub req_addgroup {
  my ($class, $req) = @_;

  $req->user_can('admin_group_add')
    or return $class->req_groups($req, "You don't have admin_group_add access");

  my $cgi = $req->cgi;
  my $name = $cgi->param('name');
  my $description = $cgi->param('description');
  my %errors;
  defined $name && length $name
    or $errors{name} = 'No name supplied';
  $description = '' unless defined $description;
  keys %errors
    and return $class->req_addgroupform($req, undef, \%errors);
  require BSE::TB::AdminGroups;
  my $old = BSE::TB::AdminGroups->getBy(name=>$name)
    and return $class->req_addgroupform($req, "Group '$name' already exists");
  my %group =
    (
     type => 'g',
     name => $name, 
     description => $description,
     perm_map => '',
    );
  my @cols = BSE::TB::AdminGroup->columns;
  shift @cols;
  my $group = BSE::TB::AdminGroups->add(@group{@cols});
  return $class->refresh($req, 'a_showgroup', groupid=>$group->{id},
			 'm' =>"Group $name created");
}

sub tag_if_user_member_of {
  my ($members, $arg, $acts, $funcname, $templater) = @_;

  my $groupid = $templater->perform($acts, $arg, 'id')
    or return;

  return exists $members->{$groupid};
}

sub iter_get_gperms {
  my ($cfg) = @_;

  require BSE::Permissions;
  my $perms = BSE::Permissions->new($cfg);

  return $perms->global_perms;
}

sub tag_if_gperm_set {
  my ($obj, $arg, $acts, $funcname, $templater) = @_;

  my $id = $templater->perform($acts, $arg, 'id');
  $id =~ /\d/
    or return;

  return unless $id < length($obj->{perm_map});

  substr($obj->{perm_map}, $id, 1);
}

sub showuser_tags {
  my ($class, $req, $user, $msg, $errors) = @_;

  my %members = map { $_->{group_id} => 1 } 
    BSE::DB->query(userGroups=>$user->{id});
  return
    (
     $class->common_tags($req, $msg, $errors),
     user => [ \&hash_tag, $user ],
     ifMemberof => [ \&tag_if_user_member_of, \%members ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_gperms, $req->cfg ], 'gperm', 'gperms' ),
     ifGperm_set =>
     [ \&tag_if_gperm_set, $user ],
    );
}

sub req_showuser {
  my ($class, $req, $msg, $errors) = @_;

  my $cgi = $req->cgi;
  my $userid = $cgi->param('userid');
  $userid
    or return $class->req_users($req, 'No userid supplied');
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getByPkey($userid)
    or return $class->req_users($req, "User id $userid not found");
  my %acts;
  %acts =
    (
     $class->showuser_tags($req, $user, $msg, $errors),
    );

  my $template = 'admin/showuser';
  my $t = $cgi->param('_t');
  $template .= "_$t" if $t && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

sub iter_get_kids {
  my ($article) = @_;

  require Articles;
  return sort { $b->{displayOrder} <=> $a->{displayOrder} } 
    Articles->children($article->{id});
}

sub iter_get_aperms {
  my ($perms) = @_;

  return $perms->article_perms;
}

sub tag_if_aperm_set {
  my ($perm, $arg, $acts, $funcname, $templater) = @_;

  return unless $perm;

  my $id = $templater->perform($acts, $arg, 'id');
  $id =~ /\d/
    or return '';

  return '' unless $id < length($perm->{perm_map});

  substr($perm->{perm_map}, $id, 1);
}

sub tag_typename {
  my ($args, $acts, $funcname, $templater) = @_;

  exists $acts->{$args} or return "** need an article name **";
  my $generator = $templater->perform($acts, $args, 'generator');

  $generator =~ /^(?:BSE::)?Generate::(\w+)$/
    or return "** invalid generator $generator **";

  return $1;
}

sub iter_crumbs {
  my ($req, $article) = @_;

  return if $article->{id} == -1;

  my @parents;
  my $work = $article;
  while ($work->{parentid} != -1) {
    $work = $work->parent;
    unshift @parents, $work;
  }

  @parents;
}

sub article_tags {
  my ($class, $req, $user, $article) = @_;

  my @children;
  my $child_index;
  my $parent;
  if ($article->{id} != -1) {
    if ($article->{parentid} != -1) {
      $parent = $article->parent;
    }
    else {
      $parent =
	{
	 id=>-1,
	 title=>'Your site',
	 generator => 'Generate::Site', # well...
	 level => 0,
	};
    }
  }
  require BSE::Permissions;
  my $perms = BSE::Permissions->new($req->cfg);
  my $perm = $perms->get_article_perm($article->{id}, $user);
  return
    (
     article => [ \&hash_tag, $article ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_kids, $article ], 'child', 'children',
      \@children, \$child_index),
     ifParent => !!$parent,
     parent => [ \&hash_tag, $parent ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_aperms, $perms ], 'aperm', 'aperms' ),
     ifAperm_set =>
     [ \&tag_if_aperm_set, $perm ],
     typename => \&tag_typename,
     articleType => escape_html
     (scalar($req->cfg->entry('level names', $article->{level}, "Site"))),
     childtype => escape_html
     (scalar($req->cfg->entry('level names', $article->{level}+1, ""))),
     DevHelp::Tags->make_iterator2
     ([ \&iter_crumbs, $req, $article ], 'crumb', 'crumbs'),
    );
}

sub get_article {
  my ($self, $id) = @_;

  if ($id eq '-1') {
    return
      {
       id=>-1,
       title=>'Your site',
       level => 0,
       parentid => 0,
      };
  }
  else {
    require Articles;
    return Articles->getByPkey($id);
  }
}

sub req_showuserart {
  my ($class, $req, $msg) = @_;

  my $cgi = $req->cgi;
  my $userid = $cgi->param('userid');
  $userid
    or return $class->req_users($req, 'No userid supplied');
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getByPkey($userid)
    or return $class->req_users($req, "User id $userid not found");
  my $artid = $cgi->param('id');
  $artid
    or return $class->req_showuser($req, 'No article id supplied');
  my $article = $class->get_article($artid)
    or return $class->req_showuser($req, 'No such article');
    
  my %acts;
  %acts =
    (
     $class->showuser_tags($req, $user, $msg),
     $class->article_tags($req, $user, $article),
    );

  my $template = 'admin/showuserart';
  my $t = $cgi->param('_t');
  $template .= "_$t" if $t && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

sub req_showgroupart {
  my ($class, $req, $msg) = @_;

  my $cgi = $req->cgi;
  my $groupid = $cgi->param('groupid');
  $groupid
    or return $class->req_groups($req, 'No groupid supplied');
  require BSE::TB::AdminGroups;
  my $group = BSE::TB::AdminGroups->getByPkey($groupid)
    or return $class->req_groups($req, "Group id $groupid not found");
  my $artid = $cgi->param('id');
  $artid
    or return $class->req_showgroup($req, 'No article id supplied');
  my $article = $class->get_article($artid)
    or return $class->req_showgroup($req, 'No such article');
    
  my %acts;
  %acts =
    (
     $class->showgroup_tags($req, $group, $msg),
     $class->article_tags($req, $group, $article),
    );

  my $template = 'admin/showgroupart';
  my $t = $cgi->param('_t');
  $template .= "_$t" if $t && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

sub req_showobjectart {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $adminid = $cgi->param('adminid');
  $adminid && $adminid =~ /^\d+$/
    or return $class->req_users($req, 'No adminid supplied');
  require BSE::TB::AdminBases;
  my $base = BSE::TB::AdminBases->getByPkey($adminid)
    or return $class->req_users($req, 'Unknown adminid');
  my $artid = $cgi->param('id');
  $artid
    or return $class->req_users($req, 'No article id supplied');
  my $article = $class->get_article($artid)
    or return $class->req_users($req, 'No such article');

  if ($base->{type} eq 'u') {
    return $class->refresh($req, a_showuserart => 
			   userid=>$adminid,
			   id=>$artid);
  }
  else {
    return $class->refresh($req, a_showgroupart => 
			   groupid=>$adminid,
			   id=>$artid);
  }
}

sub tag_if_member_of_group {
  my ($members, $arg, $acts, $funcname, $templater) = @_;

  my $userid = $templater->perform($acts, $arg, 'id')
    or return;

  return exists $members->{$userid};
}

sub showgroup_tags {
  my ($class, $req, $group, $msg, $errors) = @_;

  my %members = map { $_->{user_id} => 1 } 
    BSE::DB->query(groupUsers=>$group->{id});
  return
    (
     $class->common_tags($req, $msg, $errors),
     group => [ \&hash_tag, $group ],
     ifMemberof => [ \&tag_if_member_of_group, \%members ],
     DevHelp::Tags->make_iterator2
     ([ \&iter_get_gperms, $req->cfg ], 'gperm', 'gperms' ),
     ifGperm_set =>
     [ \&tag_if_gperm_set, $group ],
    );
}

sub req_showgroup {
  my ($class, $req, $msg, $errors) = @_;

  my $cgi = $req->cgi;
  my $groupid = $cgi->param('groupid');
  $groupid
    or return $class->req_groups($req, 'No groupid supplied');
  require BSE::TB::AdminGroups;
  my $group = BSE::TB::AdminGroups->getByPkey($groupid)
    or return $class->req_groups($req, "Group id $groupid not found");
  my %acts;
  %acts =
    (
     $class->showgroup_tags($req, $group, $msg, $errors),
    );

  my $template = 'admin/showgroup';
  my $t = $cgi->param('_t');
  $template .= "_$t" if $t && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

sub req_saveuser {
  my ($class, $req) = @_;

  $req->user_can('admin_user_save')
    or return $class->req_users($req, "You don't have admin_user_save access");

  my $cgi = $req->cgi;
  my $userid = $cgi->param('userid');
  $userid
    or return $class->req_users($req, 'No userid supplied');
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getByPkey($userid)
    or return $class->req_users($req, "User id $userid not found");

  my $name = $cgi->param('name');
  my $password = $cgi->param('password');
  my $confirm = $cgi->param('confirm');
  my %errors;
  $user->{name} = $name if defined $name;
  if (defined $password && defined $confirm
     && length $password) {
    if (length $confirm) {
      if ($password eq $confirm) {
	$user->{password} = $password;
      }
      else {
	$errors{confirm} = "Password and confirmation password didn't match"
      }
    }
    else {
      $errors{confirm} = "Enter both password and confirmation to change password";
    }
  }
  keys %errors
    and return $class->req_showuser($req, undef, \%errors);
  if ($cgi->param('savegperms') && $req->user_can('admin_user_save_gperms')) {
    my $perms = '';
    my @gperms = $cgi->param('gperms');
    for my $id (@gperms) {
      if (length($perms) < $id) {
	$perms .= '0' x ($id - length $perms);
      }
      substr($perms, $id, 1) = '1';
    }
    $user->{perm_map} = $perms;
  }
  $user->save;

  if ($cgi->param('savegroups') && $req->user_can("admin_user_save_groups")) {
    require BSE::TB::AdminGroups;
    require BSE::TB::AdminUsers;
    my @group_ids = map $_->{id}, BSE::TB::AdminGroups->all;
    my %want_groups = map { $_ => 1 } $cgi->param('groups');
    my %current_groups = map { $_->{group_id} => 1 }
      BSE::DB->query(userGroups=>$user->{id});
    
    for my $group_id (@group_ids) {
      if ($want_groups{$group_id} && !$current_groups{$group_id}) {
	BSE::DB->run(addUserToGroup=>$user->{id}, $group_id);
      }
      elsif (!$want_groups{$group_id} && $current_groups{$group_id}) {
	BSE::DB->run(delUserFromGroup=>$user->{id}, $group_id);
      }
    }
  }

  my $msg = 'User saved';
  $class->_save_htusers($req, \$msg);

  my $t = $cgi->param('_t');
  my @extras;
  push @extras, _t => $t if defined $t and $t =~ /^\w+$/;

  return $class->refresh($req, a_showuser => userid => $user->{id},
			'm' => $msg, @extras);
}

sub req_saveuserart {
  my ($class, $req) = @_;

  $req->user_can("admin_user_save_artrights")
    or return $class->req_users($req, "You don't have admin_user_save_artrights access");

  my $cgi = $req->cgi;
  my $userid = $cgi->param('userid');
  $userid
    or return $class->req_users($req, 'No userid supplied');
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getByPkey($userid)
    or return $class->req_users($req, "User id $userid not found");
  my $artid = $cgi->param('id');
  $artid
    or return $class->req_showuser($req, 'No article id supplied');
  my $article = $class->get_article($artid)
    or return $class->req_showuser($req, 'No such article');

  require BSE::Permissions;
  my $perms = BSE::Permissions->new($req->cfg);
  my $perm_map = '';
  my @aperms = $cgi->param('aperms');
  for my $id (@aperms) {
    if (length($perm_map) < $id) {
      $perm_map .= '0' x ($id - length $perm_map);
    }
    substr($perm_map, $id, 1) = '1';
  }

  $perms->set_article_perm($artid, $user, $perm_map);

  return $class->refresh($req, a_showuserart => userid => $user->{id},
			 id=>$artid, 'm' => 'Permissions saved');
}

sub req_savegroup {
  my ($class, $req, $msg) = @_;

  $req->user_can("admin_group_save")
    or return $class->req_groups($req, "You don't have admin_group_save access");

  my $cgi = $req->cgi;
  my $groupid = $cgi->param('groupid');
  $groupid
    or return $class->req_groups($req, 'No groupid supplied');
  require BSE::TB::AdminGroups;
  my $group = BSE::TB::AdminGroups->getByPkey($groupid)
    or return $class->req_groups($req, "Group id $groupid not found");
  my $description = $cgi->param('description');
  my $name = $cgi->param('name');
  $group->{description} = $description if defined $description;
  if (defined $name) {
    length $name
      or return $class->req_showgroup($req, undef, { name => 'No name supplied' });

    if (lc $name ne lc $group->{name}) {
      require BSE::TB::AdminGroups;
      my $old = BSE::TB::AdminGroups->getBy(name=>$name)
	and return $class->req_showgroup($req, undef, 
					 { name => "Group '$name' already exists" });
      $group->{name} = $name;
    }
  }

  if ($cgi->param('savegperms') && $req->user_can("admin_group_save_gperms")) {
    my $perms = '';
    my @gperms = $cgi->param('gperms');
    for my $id (@gperms) {
      if (length($perms) < $id) {
	$perms .= '0' x ($id - length $perms);
      }
      substr($perms, $id, 1) = '1';
    }
    $group->{perm_map} = $perms;
  }
  $group->save;

  if ($cgi->param('saveusers') && $req->user_can("admin_group_save_users")) {
    require BSE::TB::AdminGroups;
    require BSE::TB::AdminUsers;
    my @member_ids = map $_->{id}, BSE::TB::AdminUsers->all;
    my %want_users = map { $_ => 1 } $cgi->param('users');
    my %current_users = map { $_->{user_id} => 1 }
      BSE::DB->query(groupUsers=>$group->{id});
    
    for my $user_id (@member_ids) {
      if ($want_users{$user_id} && !$current_users{$user_id}) {
	BSE::DB->run(addUserToGroup=>$user_id, $group->{id});
      }
      elsif (!$want_users{$user_id} && $current_users{$user_id}) {
	BSE::DB->run(delUserFromGroup=>$user_id, $group->{id});
      }
    }
  }

  my $t = $cgi->param('_t');
  my @extras;
  push @extras, _t => $t if defined $t and $t =~ /^\w+$/;

  return $class->refresh($req, a_showgroup => groupid => $group->{id},
			'm' => 'Group saved', @extras);
}

sub req_savegroupart {
  my ($class, $req) = @_;

  $req->user_can("admin_group_save_artrights")
    or return $class->req_groups($req, "You don't have admin_group_save_artrights access");

  my $cgi = $req->cgi;
  my $userid = $cgi->param('userid');
  my $groupid = $cgi->param('groupid');
  $groupid
    or return $class->req_groups($req, 'No groupid supplied');
  require BSE::TB::AdminGroups;
  my $group = BSE::TB::AdminGroups->getByPkey($groupid)
    or return $class->req_groups($req, "Group id $groupid not found");
  my $artid = $cgi->param('id');
  $artid
    or return $class->req_showuser($req, 'No article id supplied');
  my $article = $class->get_article($artid)
    or return $class->req_showuser($req, 'No such article');

  require BSE::Permissions;
  my $perms = BSE::Permissions->new($req->cfg);
  my $perm_map = '';
  my @aperms = $cgi->param('aperms');
  for my $id (@aperms) {
    if (length($perm_map) < $id) {
      $perm_map .= '0' x ($id - length $perm_map);
    }
    substr($perm_map, $id, 1) = '1';
  }

  $perms->set_article_perm($artid, $group, $perm_map);

  return $class->refresh($req, a_showgroupart => groupid => $group->{id},
			 id=>$artid, 'm' => 'Permissions saved');
}

sub req_deluser {
  my ($class, $req) = @_;

  $req->user_can("admin_user_del")
    or return $class->req_users($req, "You don't have admin_user_del access");
  
  my $cgi = $req->cgi;
  my $userid = $cgi->param('userid');
  $userid
    or return $class->req_users($req, 'No userid supplied');
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getByPkey($userid)
    or return $class->req_users($req, "User id $userid not found");

  my $logon = $user->{logon};
  $user->remove;

  my $msg = "User '$logon' deleted";

  $class->_save_htusers($req, \$msg);

  return $class->refresh($req, a_users =>
			 'm' => $msg);
}

sub req_delgroup {
  my ($class, $req, $msg) = @_;

  $req->user_can("admin_group_del")
    or return $class->req_groups($req, "You don't have admin_group_del access");
  
  my $cgi = $req->cgi;
  my $groupid = $cgi->param('groupid');
  $groupid
    or return $class->req_groups($req, 'No groupid supplied');
  require BSE::TB::AdminGroups;
  my $group = BSE::TB::AdminGroups->getByPkey($groupid)
    or return $class->req_groups($req, "Group id $groupid not found");

  my $name = $group->{name};
  $group->remove;

  return $class->refresh($req, a_groups =>
			 'm' => "Group '$name' deleted");
}

1;
