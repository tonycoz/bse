package BSE::AdminUsers;
use strict;
use BSE::Util::Tags;
use HTML::Entities;
use URI::Escape;

my %actions =
  (
   users=>1,
   showuser=>1,
   saveuser=>1,
   adduser=>1,
   groups=>1,
   showgroup=>1,
   savegroup=>1,
   addgroup=>1,
  );

sub dispatch {
  my ($class, $req) = @_;

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

sub common_tags {
  my ($class, $req, $msg) = @_;

  $msg ||= $req->cgi->param('m');
  $msg ||= '';
  $msg = encode_entities($msg);
  my @users;
  my $user_index;
  my @groups;
  my $group_index;
  return
    (
     BSE::Util::Tags->admin(undef, $req->cfg),
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
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
    );
}

sub req_users {
  my ($class, $req, $msg) = @_;

  my %acts;
  %acts = $class->common_tags($req, $msg);
  return BSE::Template->get_response('admin/userlist', $req->cfg, \%acts);
}

sub req_groups {
  my ($class, $req, $msg) = @_;

  my %acts;
  %acts = $class->common_tags($req, $msg);
  return BSE::Template->get_response('admin/grouplist', $req->cfg, \%acts);
}

sub refresh {
  my ($class, $req, $target, @parms) = @_;

  my $url = $req->cfg->entryVar('site', 'url');
  $url .= $ENV{SCRIPT_NAME};
  $url .= "?$target=1";
  while (my ($key, $value) = splice @parms, 0, 2) {
    $url .= "&$key=".uri_escape($value);
  }
  return BSE::Template->get_refresh($url, $req->cfg);
}

sub hash_tag {
  my ($hash, $args) = @_;

  my $value = $hash->{$args};
  defined $value or $value = '';
  encode_entities($value);
}

sub req_adduser {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $logon = $cgi->param('logon');
  my $name = $cgi->param('name');
  my $password = $cgi->param('password');
  my $confirm = $cgi->param('confirm');
  defined $logon && length $logon
    or return $class->req_users($req, 'No logon supplied');
  $name = '' unless defined $name;
  defined $password && length $password
    or return $class->req_users($req, 'No password supplied');
  defined $confirm && length $confirm
    or return $class->req_users($req, 'No confirmation password supplied');
  $password eq $confirm
    or return $class->req_users($req, 'Password is different to confirmation password');

  require BSE::TB::AdminUsers;
  my $old = BSE::TB::AdminUsers->getBy(logon=>$logon)
    and return $class->req_users($req, "Logon '$logon' already exists");
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
  return $class->refresh($req, 'a_showuser', userid=>$user->{id},
			 m=>"User $logon created");
}

sub req_addgroup {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $name = $cgi->param('name');
  my $description = $cgi->param('description');
  defined $name && length $name
    or return $class->req_groups($req, 'No name supplied');
  $description = '' unless defined $description;

  require BSE::TB::AdminGroups;
  my $old = BSE::TB::AdminGroups->getBy(name=>$name)
    and return $class->req_groups($req, "Group '$name' already exists");
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
			 m=>"Group $name created");
}

sub req_showuser {
  my ($class, $req, $msg) = @_;

  my $cgi = $req->cgi;
  my $userid = $cgi->param('userid');
  $userid
    or return $class->req_users($req, $msg, 'No userid supplied');
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getByPkey($userid)
    or return $class->req_users($req, $msg, "User id $userid not found");
  my %acts;
  %acts =
    (
     $class->common_tags($req, $msg),
     user => [ \&hash_tag, $user ],
    );
  return BSE::Template->get_response('admin/showuser', $req->cfg, \%acts);
}

sub req_showgroup {
  my ($class, $req, $msg) = @_;

  my $cgi = $req->cgi;
  my $groupid = $cgi->param('groupid');
  $groupid
    or return $class->req_groups($req, $msg, 'No groupid supplied');
  require BSE::TB::AdminGroups;
  my $group = BSE::TB::AdminGroups->getByPkey($groupid)
    or return $class->req_groups($req, $msg, "Group id $groupid not found");
  my %acts;
  %acts =
    (
     $class->common_tags($req, $msg),
     group => [ \&hash_tag, $group ],
    );
  return BSE::Template->get_response('admin/showgroup', $req->cfg, \%acts);
}

1;
