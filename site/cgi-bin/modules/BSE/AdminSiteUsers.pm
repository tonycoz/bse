package BSE::AdminSiteUsers;
use strict;
use base qw(BSE::UI::AdminDispatch BSE::UI::SiteuserCommon);
use BSE::Util::Tags qw(tag_error_img tag_hash);
use DevHelp::HTML qw(:default popup_menu);
use SiteUsers;
use BSE::Util::Iterate;
use BSE::Util::DynSort qw(sorter tag_sorthelp);
use BSE::Util::SQL qw/now_datetime/;
use BSE::SubscriptionTypes;
use BSE::CfgInfo qw(custom_class);
use constant SITEUSER_GROUP_SECT => 'BSE Siteuser groups validation';
use BSE::Template;
use DevHelp::Date qw(dh_parse_date_sql dh_parse_time_sql);

my %actions =
  (
   list		     => 'bse_members_user_list',
   edit		     => 'bse_members_user_edit',
   save		     => 'bse_members_user_edit',
   addform	     => 'bse_members_user_add',
   add		     => 'bse_members_user_add',
   view              => 'bse_members_user_view',
   grouplist	     => 'bse_members_group_list',
   addgroupform	     => 'bse_members_group_add',
   addgroup	     => 'bse_members_group_add',
   editgroup	     => 'bse_members_group_edit',
   savegroup	     => 'bse_members_group_edit',
   deletegroupform   => 'bse_members_group_delete',
   deletegroup	     => 'bse_members_group_delete',
   groupmemberform   => 'bse_members_user_edit',
   savegroupmembers  => 'bse_members_user_edit',
   confirm           => 'bse_members_confirm',
   adduserfile       => 'bse_members_user_add_file',
   adduserfileform   => 'bse_members_user_add_file',
   edituserfile      => 'bse_members_user_edit_file',
   saveuserfile      => 'bse_members_user_edit_file',
   deluserfileform   => 'bse_members_user_del_file',
   deluserfile       => 'bse_members_user_del_file',

   addgroupfile      => 'bse_members_group_add_file',
   addgroupfileform  => 'bse_members_group_add_file',
   editgroupfile     => 'bse_members_group_edit_file',
   savegroupfile     => 'bse_members_group_edit_file',
   delgroupfileform  => 'bse_members_group_del_file',
   delgroupfile      => 'bse_members_group_del_file',
   fileaccesslog     => 'bse_members_file_log',
  );

my @donttouch = qw(id userId password email confirmed confirmSecret waitingForConfirmation flags affiliate_name previousLogon); # flags is saved separately
my %donttouch = map { $_, $_ } @donttouch;

sub default_action { 'list' }

sub actions {
  \%actions
}

sub rights {
  \%actions
}

sub flags {
  my ($cfg) = @_;

  my %flags = $cfg->entriesCS('site user flags');

  my @valid = grep /^\w+$/, keys %flags;

  return map +{ id => $_, desc => $flags{$_} },
    sort { lc($flags{$a}) cmp lc($flags{$b}) } @valid;
}

my %nosearch = map { $_ => 1 } qw/id password confirmSecret/;

sub req_list {
  my ($class, $req, $msg) = @_;
  
  my $cgi = $req->cgi;
  if ($msg) {
    $msg = escape_html($msg);
  }
  else {
    $msg = join("<br />", map escape_html($_), $cgi->param('m'));
  }
  my @users = SiteUsers->all;
  my $id = $cgi->param('id');
  defined $id or $id = '';
  my $search_done = 0;
  my %search_fields;
  if ($id =~ /^\d+$/) {
    $search_fields{id} = $id;
    @users = grep $_->{id} == $id, @users;
    ++$search_done;
  }
  else {
    my %fields;
    my @cols = grep !$nosearch{$_}, SiteUser->columns;
    for my $col (@cols, 'name') {
      my $value = $cgi->param($col);
      if (defined $value && $value =~ /\S/) {
	$fields{$col} = $value;
      }
    }
    if (keys %fields) {
      %search_fields = %fields;
      ++$search_done;
      my $name = delete $fields{name};
      if (defined $name) {
	@users = grep "$_->{name1} $_->{name2}" =~ /\Q$name/i, @users;
      }
      for my $col (keys %fields) {
	my $value_re = qr/\Q$fields{$col}/i;
	@users = grep $_->{$col} =~ /$value_re/, @users;
      }
    }
  }
  my ($sortby, $reverse) =
    sorter(data=>\@users, cgi=>$cgi, sortby=>'userId', session=>$req->session,
	   name=>'siteusers', fields=> { id => {numeric => 1 } });
  my $it = BSE::Util::Iterate->new;

  my $search_param =
    join('&', map { "$_=".escape_uri($search_fields{$_}) } keys %search_fields);
			    
  my %acts;
  %acts =
    (
     $req->admin_tags,
     message => $msg,
     $it->make_paged_iterator('siteuser', 'siteusers', \@users, undef,
			      $cgi, undef, 'pp=20', $req->session, 
			      'siteusers'),
     sortby=>$sortby,
     reverse=>$reverse,
     sorthelp => [ \&tag_sorthelp, $sortby, $reverse ],
     ifSearchDone => $search_done,
     search_param => $search_param,
    );

  return $req->dyn_response('admin/users/list', \%acts);
}

sub tag_if_required {
  my ($cfg, $args) = @_;

  return $cfg->entryBool('site users', "require_$args", 0);
}

sub iter_flags {
  my ($cfg) = @_;

  flags($cfg);
}

sub tag_if_flag_set {
  my ($flags, $arg, $acts, $funcname, $templater) = @_;

  my @args = DevHelp::Tags->get_parms($arg, $acts, $templater);
  @args or return;

  return index($flags, $args[0]) >= 0;
}

sub tag_if_subscribed_register {
  my ($cgi, $cfg, $subs, $rsub_index) = @_;

  return 0 if $$rsub_index < 0 or $$rsub_index >= @$subs;
  my $sub = $subs->[$$rsub_index];
  if ($cgi->param('checkedsubs')) {
    my @checked = $cgi->param('subscription');
    return grep($sub->{id} == $_, @checked) != 0;
  }
  else {
    my $def = $cfg->entryBool('site users', 'subscribe_all', 0);

    return $cfg->entryBool('site users', "subscribe_$sub->{id}", $def);
  }
}

sub tag_if_subscribed {
  my ($cgi, $subs, $rsub_index, $usersubs) = @_;

  $$rsub_index >= 0 && $$rsub_index < @$subs
    or return;

  my $sub = $subs->[$$rsub_index];
  if ($cgi->param('checkedsubs')) {
    my @checked = $cgi->param('subscription');
    return grep($sub->{id} == $_, @checked) != 0;
  }

  $usersubs->{$sub->{id}};
}

sub iter_orders {
  my ($siteuser) = @_;

  return $siteuser->orders;
}

sub iter_groups {
  require BSE::TB::SiteUserGroups;

  BSE::TB::SiteUserGroups->all;
}

sub tag_ifUserMember {
  my ($user, $rgroup) = @_;

  $$rgroup or return 0;

  $user->is_member_of($$rgroup);
}

sub req_edit {
  my ($class, $req, $msg, $errors) = @_;

  $class->_display_user($req, $msg, $errors, 'admin/users/edit');
}

sub req_view {
  my ($class, $req, $msg, $errors) = @_;

  $class->_display_user($req, $msg, $errors, 'admin/users/view');
}

sub _display_user {
  my ($class, $req, $msg, $errors, $template) = @_;

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  defined $id
    or return $class->req_list($req, "No site user id supplied");
  my $siteuser = SiteUsers->getByPkey($id)
    or return $class->req_list($req, "No such site user found");

  my $it = BSE::Util::Iterate->new;

  $errors ||= {};
  if ($msg) {
    $msg = escape_html($msg);
  }
  else {
    $msg = $req->message($errors);
  }

  require BSE::TB::OwnedFiles;
  my @file_cats = BSE::TB::OwnedFiles->categories($req->cfg);
  my %subbed = map { $_ => 1 } $siteuser->subscribed_file_categories;
  for my $cat (@file_cats) {
    $cat->{subscribed} = exists $subbed{$cat->{id}} ? 1 : 0;
  }

  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my $sub_index;
  require BSE::SubscribedUsers;
  my @usersubs = BSE::SubscribedUsers->getBy(userId=>$siteuser->{id});
  my %usersubs = map { $_->{subId}, $_ } @usersubs;
  my $current_group;
  my $current_file;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     message => $msg,
     siteuser => [ \&tag_hash, $siteuser ],
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     ifRequired => [ \&tag_if_required, $req->cfg ],
     $it->make_iterator([ \&iter_flags, $req->cfg], 'flag', 'flags'),
     ifFlagSet => [ \&tag_if_flag_set, $siteuser->{flags} ],
     $it->make_iterator(undef, 'subscription', 'subscriptions', \@subs, 
			\$sub_index),
     ifSubscribed =>
     [ \&tag_if_subscribed, $cgi, \@subs, \$sub_index, \%usersubs ],
     $it->make_iterator([ \&iter_orders, $siteuser ], 
			'userorder', 'userorders' ),
     $class->_edit_tags($siteuser, $req->cfg),
     $it->make_iterator(\&iter_groups, 'group', 'groups', 
			undef, undef, undef, \$current_group),
     ifMember => [ \&tag_ifUserMember, $siteuser, \$current_group ],
     $it->make_iterator([ \&iter_seminar_bookings, $siteuser],
			'booking', 'bookings'),
     $it->make
     (
      code => [ files => $siteuser ],
      single => "userfile",
      plural => "userfiles",
      store => \$current_file,
     ),
     userfile_category => [ tag_userfile_category => $class, $req, \$current_file ],
     $it->make
     (
      data => \@file_cats,
      single => "filecat",
      plural => "filecats"
     ),
    );  

  return $req->dyn_response($template, \%acts);
}

sub tag_userfile_category {
  my ($self, $req, $rfile) = @_;

  my ($current) = $req->cgi->param("category");
  unless (defined $current) {
    if ($rfile && $$rfile) {
      $current = $$rfile->category;
    }
  }
  defined $current
    or $current = "";

  require BSE::TB::OwnedFiles;
  my @all = BSE::TB::OwnedFiles->categories($req->cfg);
  return popup_menu
    (
     -name => "category",
     -default => $current,
     -values => [ map $_->{id}, @all ],
     -labels => { map { $_->{id} => $_->{name} } @all },
    );
}

sub iter_seminar_bookings {
  my ($siteuser) = @_;

  return $siteuser->seminar_bookings_detail;
}

sub req_save {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;

  my $id = $cgi->param('id');
  $id && $id =~ /^\d+$/
    or return $class->req_list($req, "No user id supplied");

  my $user = SiteUsers->getByPkey($id)
    or return $class->req_list($req, "No user $id found");

  my %errors;
  my $nopassword = $req->cfg->entry('site users', 'nopassword', 0);
  my @cols = grep !$donttouch{$_}, SiteUser->columns;
  my $custom = custom_class($cfg);
  my @required = $custom->siteuser_edit_required($req, $user);
  for my $col (@required) {
    my $value = $cgi->param($col);
    if (defined $value && $value eq '') {
      my $disp = $cfg->entry('site users', "display_$col", "\u$col");
      $errors{$col} = "$disp is a required field";
    }
  }

  my $saveemail;
  my $email = $cgi->param('email');
  if (defined $email && $email ne $user->{email} && $email ne '') {
    if ($email !~ /.\@./) {
      $errors{email} = "Email is invalid";
    }
    unless ($errors{email}) {
      if ($nopassword) {
	my $conf_email = $cgi->param('confirmemail');
	if ($conf_email) {
	  if ($conf_email eq $email) {
	    my $other = SiteUsers->getBy(userId=>$email);
	    if ($other) {
	      $errors{email} = "That email address is already in use";
	    }
	    else {
	      ++$saveemail;
	    }
	  }
	  else {
	    $errors{confirmemail} =
	      "Confirmation email address doesn't match email address";
	  }
      }
	else {
	  $errors{confirmemail} = "Please enter a confirmation email address";
	}
      }
      else {
	++$saveemail;
      }
    }
    unless ($errors{email}) {
      my $checkemail = SiteUser->generic_email($email);
      require BSE::EmailBlacklist;
      my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);
      if ($blackentry) {
	$errors{email} = "Email $email is blacklisted: $blackentry->{why}";
      }
    }
  }

  my $newpass;
  unless ($nopassword) {
    $newpass = $cgi->param('password');
    my $confirm = $cgi->param('confirm_password');
    
    if (defined $newpass && length $newpass) {
      my $min_pass_length = $cfg->entry('basic', 'minpassword') || 4;
	  my $error;
      if (length $newpass < $min_pass_length) {
	$errors{password} = "The password must be at least $min_pass_length characters";
      }
      elsif (!defined $confirm || length $confirm == 0) {
	$errors{confirm_password} = "Please enter a confirmation password";
      }
      elsif ($newpass ne $confirm) {
	$errors{confirm_password} = "The confirmation password is different from the password";
      }
    }
  }

  my $aff_name = $cgi->param('affiliate_name');
  $aff_name = _validate_affiliate_name($req, $aff_name, \%errors, $user);

  $class->_save_images($req->cfg, $req->cgi, $user, \%errors);

  keys %errors
    and return $class->req_edit($req, undef, \%errors);
  
  my $newemail;
  if ($saveemail && $email ne $user->{email}) {
    $user->{confirmed} = 0;
    $user->{confirmSecret} = '';
    $user->{email} = $email;
    $user->{userId} = $email if $nopassword;
    ++$newemail;
  }
  $user->{password} = $newpass if !$nopassword && $newpass;
  
  $user->{affiliate_name} = $aff_name if defined $aff_name;
  
  for my $col (@cols) {
    my $value = $cgi->param($col);
    if (defined $value) {
      $user->{$col} = $value;
    }
  }

  my @flags = flags($cfg);
  my %flags = map { $_->{id} => 1 } @flags;
  $user->{flags} = join('', grep exists $flags{$_}, $cgi->param('flags'))
    if $cgi->param('saveFlags');

  $user->{textOnlyMail} = 0 
    if $cgi->param('saveTextOnlyMail') && !defined $cgi->param('textOnlyMail');
  $user->{keepAddress} = 0 
    if $cgi->param('saveKeepAddress') && !defined $cgi->param('keepAddress');
  $user->{disabled} = 0
    if $cgi->param('saveDisabled') && !defined $cgi->param('disabled');
  $user->save;

  # save group membership
  my @save_ids = $cgi->param('set_group_id');
  if (@save_ids) {
    my %member_of = map { $_ => 1 } $user->group_ids;
    my %new_ids = map { $_ => 1 } $cgi->param('group_id');
    require BSE::TB::SiteUserGroups;
    my %all_groups = map { $_->{id} => $_ } BSE::TB::SiteUserGroups->all;
    
    for my $id (@save_ids) {
      my $group = $all_groups{$id} 
	or next;
      if ($member_of{$id} and !$new_ids{$id}) {
	$group->remove_member($user->{id});
	$custom->can('group_remove_member')
	  and $custom->group_remove_member($group, $user->{id}, $cfg);
      }
      elsif (!$member_of{$id} and $new_ids{$id}) {
	$group->add_member($user->{id});
	$custom->can('group_add_member')
	  and $custom->group_add_member($group, $user->{id}, $cfg);
      }
    }
  }

  if ($cgi->param('checkedsubs')) {
    $class->save_subs($req, $user);
  }

  if ($cgi->param('save_file_subs')) {
    my @new_subs = $cgi->param("file_subscriptions");
    $user->set_subscribed_file_categories($cfg, @new_subs);
  }

  $custom->siteusers_changed($cfg);
  $custom->can('siteuser_edit')
    and $custom->siteuser_edit($user, 'admin', $cfg);

  my @msgs;

  my $sent_ok = 1; # no error handling if true
  my $code;
  my $msg;
  if ($nopassword) {
    $sent_ok = $user->send_conf_request($req->cgi, $req->cfg, \$code, \$msg) 
      if $newemail;
  }
  else {
    my @subs = $user->subscriptions;
    if (@subs && !$user->{confirmed}) {
      $sent_ok = $user->send_conf_request($req->cgi, $req->cfg, \$code, \$msg);
    }
  }

  unless ($sent_ok) {
    if ($code eq 'blacklist') {
      push @msgs, "Could not send confirmation: Email address blacklisted: $msg";
    }
    elsif ($code eq 'mail') {
      push @msgs, "Could not send confirmation: Error sending email: $msg";
    }
    else {
      push @msgs, "Could not send confirmation: $msg";
    }
  }
  
  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { list => 1, m => "User saved" });
  }
  $r .= "&m=".escape_uri($_) for @msgs;

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_addform {
  my ($class, $req, $msg, $errors) = @_;

  my $cgi = $req->cgi;

  $errors ||= {};
  if ($msg) {
    $msg = escape_html($msg);
  }
  elsif ($cgi->param('m')) {
    $msg = join("<br />", map escape_html($_), $cgi->param('m'));
  }
  else {
    if (keys %$errors) {
      my %work = %$errors;
      my @msgs = grep defined, delete @work{$cgi->param()};
      push @msgs, values %work;
      $msg = join "<br />", map escape_html($_), grep $_, @msgs;
    }
    else {
      $msg = '';
    }
  }

  my $it = BSE::Util::Iterate->new;

  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my $sub_index;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     ifRequired => [ \&tag_if_required, $req->cfg ],
     $it->make_iterator([ \&iter_flags, $req->cfg], 'flag', 'flags'),
     ifFlagSet => 0,
     $it->make_iterator(undef, 'subscription', 'subscriptions', \@subs, 
			\$sub_index),
     ifSubscribed =>
     [ \&tag_if_subscribed_register, $cgi, $req->cfg, \@subs, \$sub_index ],
    );  

  return $req->dyn_response('admin/users/add', \%acts);
}

sub req_add {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;

  my %user;
  my @cols = SiteUser->columns;
  shift @cols;
  for my $field (@cols) {
    $user{$field} = '';
  }

  my $custom = custom_class($cfg);
  my @required = $custom->siteuser_add_required($req);

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  my %errors;
  my $email = $cgi->param('email');
  if (!defined $email) { # required check done later
    $email = ''; # prevent undefined value warnings later
  }
  elsif ($email !~ /.\@./) {
    $errors{email} = "Please enter a valid email address";
  }
  if ($nopassword) {
    my $confemail = $cgi->param('confirmemail');
    if (!defined $confemail or !length $confemail) {
      $errors{confirmemail} = "Please enter a confirmation email address";
    }
    elsif ($email ne $confemail) {
      $errors{confirmemail} = "Confirmation email should match the Email Address";
    }
    my $user = SiteUsers->getBy(userId=>$email);
    if ($user) {
      $errors{email} = "Sorry, email $email already exists as a user";
    }
    $user{userId} = $email;
    $user{password} = '';
  }
  else {
    my $min_pass_length = $cfg->entry('basic', 'minpassword') || 4;
    my $userid = $cgi->param('userId');
    if (!defined $userid || length $userid == 0) {
      $errors{userId} = "Please enter a userid";
    }
    my $pass = $cgi->param('password');
    my $pass2 = $cgi->param('confirm_password');
    if (!defined $pass || length $pass == 0) {
      $errors{password} = "Please enter a password";
    }
    elsif (length $pass < $min_pass_length) {
      $errors{password} = "The password must be at least $min_pass_length characters";
    }
    elsif (!defined $pass2 || length $pass2 == 0) {
      $errors{confirm_password} = "Please enter a confirmation password";
    }
    elsif ($pass ne $pass2) {
      $errors{confirm_password} = 
	"The confirmation password is different from the password";
    }
    my $user = SiteUsers->getBy(userId=>$userid);
    if ($user) {
      # give the user a suggestion
      my $workuser = $userid;
      $workuser =~ s/\d+$//;
      my $suffix = 1;
      for my $suffix (1..100) {
	unless (SiteUsers->getBy(userId=>"$workuser$suffix")) {
	  $cgi->param(userid=>"$workuser$suffix");
	  last;
	}
      }
      $errors{userId} = "Sorry, user $userid already exists";
    }
    $user{userId} = $userid;
    $user{password} = $pass;
  }

  unless ($errors{email}) {
    my $checkemail = SiteUser->generic_email($email);
    require 'BSE/EmailBlacklist.pm';
    my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);
    if ($blackentry) {
      $errors{email} = "Email $email is blacklisted: $blackentry->{why}";
    }
  }

  my @mod_cols = grep !$donttouch{$_}, @cols;
  for my $col (@mod_cols) {
    my $value = $cgi->param($col);
    if ($cfg->entryBool('site users', "require_$col")) {
      unless (defined $value && $value ne '') {
	my $disp = $cfg->entry('site users', "display_$col", "\u$col");
	
	$errors{$col} = "$disp is a required field";
      }
    }
    if (defined $value) {
      $user{$col} = $value;
    }
  }

  my $aff_name = $cgi->param('affiliate_name');
  $aff_name = _validate_affiliate_name($req, $aff_name, \%errors);
  defined $aff_name or $aff_name = '';

  if (keys %errors) {
    return $class->req_addform($req, undef, \%errors);
  }

  $user{email} = $email;
  $user{lastLogon} = $user{whenRegistered} = 
    $user{previousLogon} = now_datetime;
  $user{keepAddress} = 0;
  $user{wantLetter} = 0;
  $user{affiliate_name} = $aff_name;
  if ($nopassword) {
    use BSE::Util::Secure qw/make_secret/;
    $user{password} = make_secret($cfg);
  }
  my @flags = flags($cfg);
  my %flags = map { $_->{id} => 1 } @flags;
  $user{flags} = join('', grep exists $flags{$_}, $cgi->param('flags'));

  my $user;
  eval {
    $user = SiteUsers->add(@user{@cols});
  };
  if ($user) {
    my $subs = $class->save_subs($req, $user);
    my $msg;
    if ($nopassword) {
      my $code;
      my $sent_ok = $user->send_conf_request($cgi, $cfg, \$code, \$msg);
    }
    else {
      if ($subs) {
	my $code;
	my $sent_ok = $user->send_conf_request($cgi, $cfg, \$code, \$msg);
      }
    }
    
    $custom->siteusers_changed($cfg);
    $custom->can('siteuser_add')
      and $custom->siteuser_add($user, 'admin', $cfg);

    my $r = $cgi->param('r');
    unless ($r) {
      $r = $req->url('siteusers', { list => 1, 
				    'm' => "User $user->{userId} added" });
    }
    $r .= "&m=".escape_uri($msg) if $msg;
    return BSE::Template->get_refresh($r, $cfg);
  }
  else {
    $class->req_add($req, "Database error $@");
  }
}

sub save_subs {
  my ($class, $req, $user) = @_;

  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my %subs = map { $_->{id} => $_ } @subs;
  my @subids = $req->cgi->param('subscription');
  $user->removeSubscriptions;
  require BSE::SubscribedUsers;
  my @cols = BSE::SubscribedUser->columns;
  shift @cols;
  my $found = 0;
  for my $id (@subids) {
    if ($subs{$id}) {
      my %usersub;
      $usersub{subId} = $id;
      $usersub{userId} = $user->{id};

      BSE::SubscribedUsers->add(@usersub{@cols});
      ++$found;
    }
  }

  $found;
}

sub _validate_affiliate_name {
  my ($req, $aff_name, $errors, $user) = @_;

  my $display = $req->cfg->entry('site users', 'display_affiliate_name',
				 "Affiliate name");
  my $required = $req->cfg->entry('site users', 'require_affiliate_name', 0);

  if (defined $aff_name) {
    $aff_name =~ s/^\s+|\s+$//g;
    if (length $aff_name) {
      if ($aff_name =~ /^\w+$/) {
	my $other = SiteUsers->getBy(affiliate_name => $aff_name);
	if ($other && (!$user || $other->{id} != $user->{id})) {
	  $errors->{affiliate_name} = "$display $aff_name is already in use";
	}
	else {
	  return $aff_name;
	}
      }
      else {
	$errors->{affiliate_name} = "invalid $display, no spaces or special characters are allowed";
      }
    }
    elsif ($required) {
      $errors->{affiliate_name} = "$display is a required field";
    }
    else {
      return '';
    }
  }

  # always required if making a new user
  if (!$errors->{affiliate_name} && $required && !$user) {
    $errors->{affiliate_name} = "$display is a required field";
  }

  return;
}

sub _get_group {
  my ($req, $msg) = @_;

  my $id = $req->cgi->param('id');
  defined $id && $id =~ /^-?\d+$/
    or do { $$msg = "Missing or invalid group id"; return };

  my $group;
  require BSE::TB::SiteUserGroups;
  if ($id < 0) {
    $group = BSE::TB::SiteUserGroups->getQueryGroup($req->cfg, $id);
  }
  else {
    $group = BSE::TB::SiteUserGroups->getByPkey($id);
  }
  $group
    or do { $$msg = "Unknown group id"; return };

  $group;
}

sub req_grouplist {
  my ($class, $req, $errors) = @_;

  require BSE::TB::SiteUserGroups;
  my @groups = BSE::TB::SiteUserGroups->admin_and_query_groups($req->cfg);

  my $msg = $req->message($errors);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     msg=>$msg,
     message=>$msg,
     $it->make_iterator(undef, 'group', 'groups', \@groups),
    );

  return $req->dyn_response('admin/users/grouplist', \%acts);
}

sub req_addgroupform {
  my ($class, $req, $errors) = @_;

  my $msg = $req->message($errors);

  my %acts;
  %acts =
    (
     $req->admin_tags,
     msg=>$msg,
     message=>$msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return $req->dyn_response('admin/users/groupadd', \%acts);
}

sub req_addgroup {
  my ($class, $req) = @_;

  require BSE::TB::SiteUserGroups;
  my %fields = BSE::TB::SiteUserGroup->valid_fields;
  my %rules = BSE::TB::SiteUserGroup->valid_rules;

  my %errors;
  $req->validate(errors=>\%errors,
		 fields=>\%fields,
		 rules=>\%rules,
		 section=>SITEUSER_GROUP_SECT)
    or return $class->req_addgroupform($req, \%errors);

  my $cgi = $req->cgi;
  my $name = $cgi->param('name');
  my $group = BSE::TB::SiteUserGroups->add($name);

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_grouplist => 1, m => "Group created" });
  }
  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_editgroup {
  my ($class, $req, $errors) = @_;

  return $class->_common_group($req, $errors, 'admin/users/groupedit');
}

sub req_savegroup {
  my ($class, $req) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $class->req_grouplist($req, { id => $msg });

  my %fields = BSE::TB::SiteUserGroup->valid_fields;
  my %rules = BSE::TB::SiteUserGroup->valid_rules;

  my %errors;
  $req->validate(errors=>\%errors,
		 fields=>\%fields,
		 rules=>\%rules,
		 section=>SITEUSER_GROUP_SECT)
    or return $class->req_editgroup($req, \%errors);

  my $cgi = $req->cgi;
  $group->{name} = $cgi->param('name');
  $group->save;

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_grouplist => 1, m => "Group saved" });
  }
  return BSE::Template->get_refresh($r, $req->cfg);
}

sub _common_group {
  my ($class, $req, $errors, $template) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $class->req_grouplist($req, { id=> $msg });

  $msg = $req->message($errors);
  my $it = BSE::Util::Iterate->new;
  my $current_file;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     msg=>$msg,
     message=>$msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     group => [ \&tag_hash, $group ],
     $it->make
     (
      code => [ files => $group ],
      single => "groupfile",
      plural => "groupfiles",
      store => \$current_file,
     ),
    );

  return $req->dyn_response($template, \%acts);
}

sub req_deletegroupform {
  my ($class, $req, $errors) = @_;

  return $class->_common_group($req, $errors, 'admin/users/groupdelete');
}

sub req_deletegroup {
  my ($class, $req) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $class->req_grouplist($req, { id=>$msg });

  $group->remove;

  my $r = $req->cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_grouplist => 1, m => "Group deleted" });
  }
  return BSE::Template->get_refresh($r, $req->cfg);
}

sub tag_ifMember {
  my ($ruser, $members) = @_;

  $$ruser or return 0;
  exists $members->{$$ruser->{id}};
}

sub req_groupmemberform {
  my ($class, $req, $errors) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $class->req_grouplist($req, { id=>$msg });

  $msg = $req->message($errors);

  my %members = map { $_=> 1 } $group->member_ids;
  my @siteusers = SiteUsers->all;

  my $user;

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $req->admin_tags,
     msg=>$msg,
     message=>$msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     group => [ \&tag_hash, $group ],
     $it->make_iterator(undef, 'siteuser', 'siteusers', \@siteusers, 
			undef, undef, \$user),
     ifMember => [ \&tag_ifMember, \$user, \%members ],
    );

  return $req->dyn_response('admin/users/groupmembers', \%acts);
}

sub req_savegroupmembers {
  my ($class, $req) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $class->req_grouplist($req, { id=>$msg });

  my $cgi = $req->cgi;
  my %current_ids = map { $_ => 1 } $group->member_ids;
  my @to_be_set = $cgi->param('set_is_member');
  my %set_ids = map { $_ => 1 } $cgi->param('is_member');
  my %all_ids = map { $_ => 1 } SiteUsers->all_ids;

  my $custom = custom_class($req->cfg);

  for my $id (@to_be_set) {
    next unless $all_ids{$id};

    if ($set_ids{$id} && !$current_ids{$id}) {
      $group->add_member($id);
	$custom->can('group_add_member')
	  and $custom->group_add_member($group, $id, $req->cfg);
    }
    elsif (!$set_ids{$id} && $current_ids{$id}) {
      $group->remove_member($id);
      $custom->can('group_remove_member')
	and $custom->group_remove_member($group, $id, $req->cfg);
    }
  }

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_grouplist => 1, m => "Membership saved" });
  }
  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_confirm {
  my ($class, $req) = @_;

  $ENV{REMOTE_USER} || $req->getuser
    or return $class->error($req, 
			   { error => "You must be authenticated to use this function.  Either enable access control or setup .htpasswd." });

  my $cgi = $req->cgi;
  my $id = $cgi->param('id');
  defined $id
    or return $class->req_list($req, "No site user id supplied");
  my $siteuser = SiteUsers->getByPkey($id)
    or return $class->req_list($req, "No such site user found");

  $siteuser->{confirmed} = 1;
  $siteuser->save;

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { list => 1, m => "User confirmed" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

my %file_fields =
  (
   content_type => 
   {
    description => "Content type",
    rules => "dh_one_line",
   },
   category =>
   {
    description => "Category",
    rules => "dh_one_line",
   },
   modwhen_date =>
   {
    description => "Last Modified date",
    rules => "date",
    requried_if => "modwhen_time",
   },
   modwhen_time =>
   {
    description => "Last Modified time",
    rules => "time",
    required_if => "modwhen_date",
   },
   title =>
   {
    description => "Title",
    rules => "dh_one_line",
   },
   body =>
   {
    description => "Body",
   },
  );

my %save_file_fields =
  (
   content_type => 
   {
    description => "Content type",
    rules => "dh_one_line",
   },
   category =>
   {
    description => "Category",
    rules => "dh_one_line",
   },
   modwhen_date =>
   {
    description => "Last Modified date",
    rules => "date",
    requried => 1,
   },
   modwhen_time =>
   {
    description => "Last Modified time",
    rules => "time",
    required => 1,
   },
   title =>
   {
    description => "Title",
    rules => "dh_one_line",
    required => 1,
   },
   body =>
   {
    description => "Body",
   },
  );

sub req_adduserfileform {
  my ($self, $req, $errors) = @_;

  my $msg;
  my $siteuser = _get_user($req, \$msg)
    or return $self->req_list($req, $msg);

  my %acts =
    (
     $req->admin_tags,
     message => $msg,
     siteuser => [ \&tag_hash, $siteuser ],
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     userfile_category => [ tag_userfile_category => $self, $req, undef ],
    );

  return $req->dyn_response("admin/users/add_user_file", \%acts);
}

sub req_adduserfile {
  my ($self, $req) = @_;

  my $msg;
  my $user = _get_user($req, \$msg)
    or return $self->req_list($req, $msg);

  my $cgi = $req->cgi;

  $req->check_csrf("admin_user_add_file")
    or return $self->csrf_error($req, "admin_user_add_file", "Add Member File");

  my %errors;
  $req->validate(fields => \%file_fields,
		 errors => \%errors);

  my $file = $cgi->param("file");
  my $file_fh = $cgi->upload("file");
  unless ($file) {
    $errors{file} = "Please select a file";
  }
  if ($file && -z $file) {
    $errors{file} = "File is empty";
  }
  if (!$errors{$file} && !$file_fh) {
    $errors{file} = "Something is wrong with the upload form or your file wasn't found";
  }

  keys %errors
    and return $self->req_adduserfileform($req, undef, \%errors);

  require BSE::API;
  BSE::API->import("bse_add_owned_file");

  my %file;
  $file{file} = $file_fh;
  for my $field (qw/content_type category title body/) {
    my ($value) = $cgi->param($field);
    defined $value or $value = "";
    $file{$field} = $value;
  }
  $file{download} = $cgi->param('download') ? 1 : 0;
  my $mod_date = $cgi->param("modwhen_date");
  my $mod_time = $cgi->param("modwhen_time");
  if ($mod_date && $mod_time) {
    $file{modwhen} = dh_parse_date_sql($mod_date) . " " 
      . dh_parse_time_sql($mod_time);
  }
  $file{display_name} = $file . "";
  my $upload_info = $cgi->uploadInfo($file);
# some content types come through strangely
#  if (!$file{content_type} && $upload_info->{"Content-Type"}) {
#    $file{content_type} = $upload_info->{"Content-Type"}
#  }
  for my $key (keys %$upload_info) {
    print STDERR "uploadinfo: $key: $upload_info->{$key}\n";
  }
  local $SIG{__DIE__};
  my $owned_file = eval { bse_add_owned_file($req->cfg, $user, %file) };
  unless ($owned_file) {
    $errors{file} = $@;
    return $self->req_edit($req, undef, \%errors);
  }

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_edit => 1, _t => "files", id => $user->id, m => "File created" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub _get_user_file {
  my ($req, $user, $msg) = @_;

  my $file_id = $req->cgi->param("file_id");
  unless (defined $file_id && $file_id =~ /^\d+$/) {
    $$msg = "Missing or invalid file id";
    return;
  }
  require BSE::TB::OwnedFiles;
  my ($file) = BSE::TB::OwnedFiles->getBy
    (
     owner_type => $user->file_owner_type,
     owner_id => $user->id,
     id => $file_id
    );
  unless ($file) {
    $$msg = "No such file found";
    return;
  }

  return $file;
}

sub _show_userfile {
  my ($self, $req, $template, $siteuser, $file, $errors) = @_;

  my $message = $req->message($errors);

  my %acts =
    (
     $req->admin_tags,
     userfile => [ \&tag_hash, $file ],
     message => $message,
     siteuser => [ \&tag_hash, $siteuser ],
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     userfile_category => [ tag_userfile_category => $self, $req, \$file ],
    );

  return $req->dyn_response($template, \%acts);
}

sub req_edituserfile {
  my ($self, $req, $errors) = @_;

  my $msg;
  my $siteuser = _get_user($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_user_file($req, $siteuser, \$msg)
    or return $self->req_list($req, $msg);

  return $self->_show_userfile($req, "admin/users/edit_user_file", $siteuser, $file, $errors);
}

sub req_deluserfileform {
  my ($self, $req, $errors) = @_;

  my $msg;
  my $siteuser = _get_user($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_user_file($req, $siteuser, \$msg)
    or return $self->req_list($req, $msg);

  return $self->_show_userfile($req, "admin/users/delete_user_file", $siteuser, $file, $errors);
}

sub req_saveuserfile {
  my ($self, $req) = @_;

  $req->check_csrf("admin_user_edit_file")
    or return $self->csrf_error($req, "admin_user_edit_file", "Edit Member File");

  my $msg;
  my $siteuser = _get_user($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_user_file($req, $siteuser, \$msg)
    or return $self->req_list($req, $msg);

  my %errors;
  $req->validate(fields => \%file_fields,
		 errors => \%errors);

  my %changes;
  my $cgi = $req->cgi;
  my $new_file = $cgi->param("file");
  my $new_fh = $cgi->upload("file");

  if ($new_file) {
    if (!$new_fh) {
      $errors{file} = "Something is wrong with the upload form or your file wasn't found";
    }
  }
  unless ($errors{file}) {
    -z $new_file
      and $errors{file} = "File is empty";
  }

  keys %errors
    and return $self->req_edituserfile($req, \%errors);

  for my $field (qw/content_type category title body/) {
    my ($value) = $cgi->param($field);
    defined $value
      and $changes{$field} = $value;
  }
  if ($new_file && $new_fh) {
    $changes{file} = $new_fh;
    $changes{display_name} = $new_file;
    my $upload_info = $cgi->uploadInfo($new_file);
# some content types come through strangely
#    if (!$changes{content_type} && $upload_info->{"Content-Type"}) {
#      $changes{content_type} = $upload_info->{"Content-Type"}
#    }
  }
  if (defined $changes{content_type} && !$changes{content_type} =~ /\S/) {
    $errors{content_type} = "Content type must be set";
  }
  $changes{download} = $cgi->param('download') ? 1 : 0;
  my $mod_date = $cgi->param("modwhen_date");
  my $mod_time = $cgi->param("modwhen_time");
  if ($mod_date && $mod_time) {
    $changes{modwhen} = dh_parse_date_sql($mod_date) . " " 
      . dh_parse_time_sql($mod_time);
  }

  require BSE::API;
  BSE::API->import("bse_replace_owned_file");
  my $good = eval { bse_replace_owned_file($req->cfg, $file, %changes); };

  $good
    or return $self->req_edituserfile($req, { _ => $@ });
  
  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_edit => 1, _t => "files", id => $siteuser->id, m => "File saved" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_deluserfile {
  my ($self, $req) = @_;

  $req->check_csrf("admin_user_del_file")
    or return $self->csrf_error($req, "admin_user_del_file", "Delete Member File");

  my $msg;
  my $siteuser = _get_user($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_user_file($req, $siteuser, \$msg)
    or return $self->req_list($req, $msg);

  require BSE::API;
  BSE::API->import("bse_delete_owned_file");
  my $good = eval { bse_delete_owned_file($req->cfg, $file); };

  $good
    or return $self->req_deluserfileform($req, { _ => $@ });

  my $r = $req->cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_edit => 1, _t => "files", id => $siteuser->id, m => "File removed" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_addgroupfileform {
  my ($self, $req, $errors) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $self->req_list($req, $msg);

  my %acts =
    (
     $req->admin_tags,
     message => $msg,
     group => [ \&tag_hash, $group ],
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     userfile_category => [ tag_userfile_category => $self, $req, undef ],
    );

  return $req->dyn_response("admin/users/add_group_file", \%acts);
}

sub req_addgroupfile {
  my ($self, $req) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $self->req_list($req, $msg);

  my $cgi = $req->cgi;

  $req->check_csrf("admin_group_add_file")
    or return $self->csrf_error($req, "admin_group_add_file", "Add Member File");

  my %errors;
  $req->validate(fields => \%file_fields,
		 errors => \%errors);

  my $file = $cgi->param("file");
  my $file_fh = $cgi->upload("file");
  unless ($file) {
    $errors{file} = "Please select a file";
  }
  if ($file && -z $file) {
    $errors{file} = "File is empty";
  }
  if (!$errors{$file} && !$file_fh) {
    $errors{file} = "Something is wrong with the upload form or your file wasn't found";
  }

  keys %errors
    and return $self->req_addgroupfileform($req, undef, \%errors);

  require BSE::API;
  BSE::API->import("bse_add_owned_file");

  my %file;
  $file{file} = $file_fh;
  for my $field (qw/content_type category title body/) {
    my ($value) = $cgi->param($field);
    defined $value or $value = "";
    $file{$field} = $value;
  }
  $file{download} = $cgi->param('download') ? 1 : 0;
  my $mod_date = $cgi->param("modwhen_date");
  my $mod_time = $cgi->param("modwhen_time");
  if ($mod_date && $mod_time) {
    $file{modwhen} = dh_parse_date_sql($mod_date) . " " 
      . dh_parse_time_sql($mod_time);
  }
  $file{display_name} = $file . "";
  my $upload_info = $cgi->uploadInfo($file);
# some content types come through strangely
#  if (!$file{content_type} && $upload_info->{"Content-Type"}) {
#    $file{content_type} = $upload_info->{"Content-Type"}
#  }
  for my $key (keys %$upload_info) {
    print STDERR "uploadinfo: $key: $upload_info->{$key}\n";
  }
  local $SIG{__DIE__};
  my $owned_file = eval { bse_add_owned_file($req->cfg, $group, %file) };
  unless ($owned_file) {
    $errors{file} = $@;
    return $self->req_edit($req, undef, \%errors);
  }

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_editgroup => 1, _t => "files", id => $group->id, m => "File created" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub _get_group_file {
  my ($req, $group, $msg) = @_;

  my $file_id = $req->cgi->param("file_id");
  unless (defined $file_id && $file_id =~ /^\d+$/) {
    $$msg = "Missing or invalid file id";
    return;
  }
  require BSE::TB::OwnedFiles;
  my ($file) = BSE::TB::OwnedFiles->getBy
    (
     owner_type => $group->file_owner_type,
     owner_id => $group->id,
     id => $file_id
    );
  unless ($file) {
    $$msg = "No such file found";
    return;
  }

  return $file;
}

sub _show_groupfile {
  my ($self, $req, $template, $group, $file, $errors) = @_;

  my $message = $req->message($errors);

  my %acts =
    (
     $req->admin_tags,
     groupfile => [ \&tag_hash, $file ],
     message => $message,
     group => [ \&tag_hash, $group ],
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     userfile_category => [ tag_userfile_category => $self, $req, \$file ],
    );

  return $req->dyn_response($template, \%acts);
}

sub req_editgroupfile {
  my ($self, $req, $errors) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_group_file($req, $group, \$msg)
    or return $self->req_list($req, $msg);

  return $self->_show_groupfile($req, "admin/users/edit_group_file", $group, $file, $errors);
}

sub req_delgroupfileform {
  my ($self, $req, $errors) = @_;

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_group_file($req, $group, \$msg)
    or return $self->req_list($req, $msg);

  return $self->_show_groupfile($req, "admin/users/delete_group_file", $group, $file, $errors);
}

sub req_savegroupfile {
  my ($self, $req) = @_;

  $req->check_csrf("admin_group_edit_file")
    or return $self->csrf_error($req, "admin_group_edit_file", "Edit Member File");

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_group_file($req, $group, \$msg)
    or return $self->req_list($req, $msg);

  my %errors;
  $req->validate(fields => \%file_fields,
		 errors => \%errors);

  my %changes;
  my $cgi = $req->cgi;
  my $new_file = $cgi->param("file");
  my $new_fh = $cgi->upload("file");

  if ($new_file) {
    if (!$new_fh) {
      $errors{file} = "Something is wrong with the upload form or your file wasn't found";
    }
  }
  unless ($errors{file}) {
    -z $new_file
      and $errors{file} = "File is empty";
  }

  keys %errors
    and return $self->req_editgroupfile($req, \%errors);

  for my $field (qw/content_type category title body/) {
    my ($value) = $cgi->param($field);
    defined $value
      and $changes{$field} = $value;
  }
  if ($new_file && $new_fh) {
    $changes{file} = $new_fh;
    $changes{display_name} = $new_file;
    my $upload_info = $cgi->uploadInfo($new_file);
# some content types come through strangely
#    if (!$changes{content_type} && $upload_info->{"Content-Type"}) {
#      $changes{content_type} = $upload_info->{"Content-Type"}
#    }
  }
  if (defined $changes{content_type} && !$changes{content_type} =~ /\S/) {
    $errors{content_type} = "Content type must be set";
  }
  $changes{download} = $cgi->param('download') ? 1 : 0;
  my $mod_date = $cgi->param("modwhen_date");
  my $mod_time = $cgi->param("modwhen_time");
  if ($mod_date && $mod_time) {
    $changes{modwhen} = dh_parse_date_sql($mod_date) . " " 
      . dh_parse_time_sql($mod_time);
  }

  require BSE::API;
  BSE::API->import("bse_replace_owned_file");
  my $good = eval { bse_replace_owned_file($req->cfg, $file, %changes); };

  $good
    or return $self->req_editgroupfile($req, { _ => $@ });
  
  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_editgroup => 1, _t => "files", id => $group->id, m => "File saved" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_delgroupfile {
  my ($self, $req) = @_;

  $req->check_csrf("admin_group_del_file")
    or return $self->csrf_error($req, "admin_group_del_file", "Delete Member File");

  my $msg;
  my $group = _get_group($req, \$msg)
    or return $self->req_list($req, $msg);

  my $file = _get_group_file($req, $group, \$msg)
    or return $self->req_list($req, $msg);

  require BSE::API;
  BSE::API->import("bse_delete_owned_file");
  my $good = eval { bse_delete_owned_file($req->cfg, $file); };

  $good
    or return $self->req_delgroupfileform($req, { _ => $@ });

  my $r = $req->cgi->param('r');
  unless ($r) {
    $r = $req->url('siteusers', { a_editgroup => 1, _t => "files", id => $group->id, m => "File removed" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub _get_user {
  my ($req, $msg) = @_;

  my $id = $req->cgi->param('id');
  defined $id && $id =~ /^\d+$/
    or do { $$msg = "Missing or invalid user id"; return };
  require BSE::TB::SiteUserGroups;
  my $group = SiteUsers->getByPkey($id);
  $group
    or do { $$msg = "Unknown user id"; return };

  $group;
}

sub csrf_error {
  my ($self, $req, $name, $description) = @_;

  my %errors;
  my $msg = $req->csrf_error;
  $errors{_csrfp} = $msg;
  return $self->req_list($req, "$description: $msg ($name)");
}

sub tag_page_args {
  my ($self, $page_args, $args) = @_;

  my %args = %$page_args;
  if ($args) {
    delete @args{split ' ', $args};
  }

  return join "&amp;", map { "$_=" . escape_uri($args{$_}) } keys %args;
}

sub tag_page_argsh {
  my ($self, $page_args, $args) = @_;

  my %args = %$page_args;
  if ($args) {
    delete @args{split ' ', $args};
  }

  return join "", map 
    { 
      my $value = escape_html($args{$_});
      qq(<input type="hidden" name="$_" value="$value" />);
    } keys %args;
}

sub tag_fileaccess_user {
  my ($rcurrent, $cache) = @_;
  
  $$rcurrent
    or return '';
  my $id = $$rcurrent->siteuser_id;
  exists $cache->{$id}
    or $cache->{$id} = SiteUsers->getByPkey($id);

  $cache->{$id}
    or return "** No user $id";

  return escape_html($cache->{$id}->userId);
}

sub tag_ifFileuser {
  my ($rcurrent, $cache) = @_;
  
  $$rcurrent
    or return '';
  my $id = $$rcurrent->siteuser_id;
  exists $cache->{$id}
    or $cache->{$id} = SiteUsers->getByPkey($id);

  return defined $cache->{$id};
}

sub _find_file_owner {
  my ($owner_type, $owner_id, $cfg, $cache) = @_;

  require BSE::TB::SiteUserGroups;
  my $owner;
  if ($owner_type eq SiteUser->file_owner_type) {
    if ($cache->{$owner_id} ||= SiteUsers->getByPkey($owner_id)) {
      $owner = $cache->{$owner_id}->data_only;
      $owner->{desc} = "User: " . $owner->{userId};
    }
    else {
      return;
    }
  }
  elsif ($owner_type eq BSE::TB::SiteUserGroup->file_owner_type) {
    my $group;
    if ($owner_id < 0) {
      $group = BSE::TB::SiteUserGroups->getQueryGroup($cfg, $owner_id);
    }
    else {
      $group = BSE::TB::SiteUserGroups->getByPkey($owner_id);
    }
    $group
      or return;
    $owner = $group->data_only;
    $owner->{desc} = "Group: " . $group->{name};
  }
  else {
    print STDERR "** Unknown file owner type $owner_type\n";
    return;
  }

  return $owner;
}

sub tag_fileowner {
  my ($rcurrent, $cache, $cfg, $args) = @_;

  $$rcurrent or return "";

  my $owner = _find_file_owner($$rcurrent->{owner_type}, $$rcurrent->{owner_id}, $cfg, $cache)
    or return "Unknown";

  return tag_hash($owner, $args);
}

sub tag_filecat {
  my ($rcurrent, $cats) = @_;

  $$rcurrent
    or return '';

  $cats->{$$rcurrent->{category}};
}

sub req_fileaccesslog {
  my ($self, $req) = @_;

  my @filters;
  my $cgi = $req->cgi;
  my %page_args;
  my $file_id = $cgi->param("file_id");
  my $file;
  if ($file_id && $file_id =~ /^\d+$/) {
    require BSE::TB::OwnedFiles;
    $file = BSE::TB::OwnedFiles->getByPkey($file_id);
    if ($file) {
      push @filters, [ '=', file_id => $file_id ];
      $page_args{file_id} = $file_id;
    }
  }
  my $siteuser_id = $cgi->param('siteuser_id');
  my $user;
  if ($siteuser_id && $siteuser_id =~ /^\d+$/) {
    $user = SiteUsers->getByPkey($siteuser_id);
    if ($user) {
      push @filters, [ '=', siteuser_id => $siteuser_id ];
      $page_args{siteuser_id} = $siteuser_id;
    }
  }
  my $owner_id = $cgi->param("owner_id");
  my $owner_type = $cgi->param("owner_type") || "U";
  my $owner;
  my $owner_desc = '';
  my %user_cache;
  if (defined $owner_id) {
    push @filters,
      (
       [ '=', owner_id => $owner_id ],
       [ '=', owner_type => $owner_type ],
      );
    $owner = _find_file_owner($owner_type, $owner_id, $req->cfg, \%user_cache);
    if ($owner) {
      $owner_desc = $owner->{desc};
    }
    if ($owner) {
      $page_args{owner_type} = $owner_type;
      $page_args{owner_id} = $owner_id;
    }
  }

  require BSE::TB::OwnedFiles;
  my %categories = map { $_->{id} => escape_html($_->{name}) } 
    BSE::TB::OwnedFiles->categories($req->cfg);

  my $category_id = $cgi->param("category");
  my $category;
  if (defined $category_id && $categories{$category_id}) {
    $category = $categories{$category_id};
    push @filters,
      [ "=", category => $category_id ];
    $page_args{category} = $category_id;
  }
  use POSIX qw(strftime);
  my %errors;
  my $from = $cgi->param("from") || strftime("%d/%m/%Y", localtime(time()-30*86400));
  my $to = $cgi->param("to") || strftime("%d/%m/%Y", localtime);
  my $from_sql = dh_parse_date_sql($from)
    or $errors{from_sql} = "Invalid from date";
  my $to_sql = dh_parse_date_sql($to)
    or $errors{to_sql} = "Invalid to date";

  require BSE::TB::FileAccessLog;
  my @entries;
  unless (keys %errors) {
    push @filters, [ between => when_at => $from_sql, "$to_sql 23:59:59" ];
    $cgi->param(from => $from);
    $cgi->param(to => $to);
    $page_args{from} = $from;
    $page_args{to} = $to;
    @entries = map $_->{id}, BSE::TB::FileAccessLog->query
      (
       [ qw/id/ ],
       \@filters,
       {
	order => 'when_at desc'
       },
      );
  }

  my $it = BSE::Util::Iterate->new;
  my $current_access;
  my %acts =
    (
     $req->admin_tags,
     $it->make_paged
     (
      data => \@entries,
      fetch => [ getByPkey => 'BSE::TB::FileAccessLog' ],
      cgi => $req->cgi,
      single => "fileaccess",
      plural => "fileaccesses",
      store => \$current_access,
      name => "fileaccesses",
      session => $req->session,
      perpage_parm => "pp=100",
     ),
     ifOwner => defined $owner,
     owner => [ \&tag_hash, $owner ],
     owner_type => (defined $owner_type ? $owner_type : ''),
     owner_desc => escape_html($owner_desc),
     ifSiteuser => defined $user,
     siteuser => [ \&tag_hash, $user ],
     ifFile => defined $file,
     file => [ \&tag_hash, $file ],
     page_args => [ tag_page_args => $self, \%page_args ],
     page_argsh => [ tag_page_argsh => $self, \%page_args ],
     user => [ \&tag_fileaccess_user, \$current_access, \%user_cache ],
     ifFileuser => [ \&tag_ifFileuser, \$current_access, \%user_cache ],
     fileowner => [ \&tag_fileowner, \$current_access, \%user_cache, $req->cfg ],
     filecat => [ \&tag_filecat, \$current_access, \%categories ],
     error_img =>[ \&tag_error_img, $req->cfg, \%errors ],
     ifCategory => $category,
     category => escape_html($category),
    );

  return $req->dyn_response("admin/users/fileaccess", \%acts);
}

1;
