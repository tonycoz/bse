package BSE::AdminSiteUsers;
use strict;
use base qw(BSE::UI::SiteuserCommon);
use BSE::Util::Tags qw(tag_error_img tag_hash);
use DevHelp::HTML;
use SiteUsers;
use BSE::Util::Iterate;
use BSE::Util::DynSort qw(sorter tag_sorthelp);
use BSE::Util::SQL qw/now_datetime/;
use BSE::SubscriptionTypes;
use BSE::CfgInfo qw(custom_class);

my %actions =
  (
   list=>1,
   edit=>1,
   save=>1,
   addform=>1,
   add=>1,
  );

my @donttouch = qw(id userId password email confirmed confirmSecret waitingForConfirmation flags affiliate_name previousLogon); # flags is saved separately
my %donttouch = map { $_, $_ } @donttouch;

sub dispatch {
  my ($class, $req) = @_;

  $req->check_admin_logon()
    or return BSE::Template->get_refresh($req->url('logon'), $req->cfg);

  my $cgi = $req->cgi;
  my $action;
  for my $check (keys %actions) {
    if ($cgi->param("a_$check")) {
      $action = $check;
      last;
    }
  }
  $action ||= 'list';
  my $method = "req_$action";
  $class->$method($req);
}

sub flags {
  my ($cfg) = @_;

  my %flags = $cfg->entriesCS('site user flags');

  my @valid = grep /^\w+$/, keys %flags;

  return map +{ id => $_, desc => $flags{$_} },
    sort { lc($flags{$a}) cmp lc($flags{$b}) } @valid;
}

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
  my ($sortby, $reverse) =
    sorter(data=>\@users, cgi=>$cgi, sortby=>'userId', session=>$req->session,
	   name=>'siteusers', fields=> { id => {numeric => 1 } });
  my $it = BSE::Util::Iterate->new;
			    
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     BSE::Util::Tags->admin(undef, $req->cfg),
     message => $msg,
     $it->make_paged_iterator('siteuser', 'siteusers', \@users, undef,
			      $cgi, undef, 'pp=20', $req->session, 
			      'siteusers'),
     sortby=>$sortby,
     reverse=>$reverse,
     sorthelp => [ \&tag_sorthelp, $sortby, $reverse ],
    );

  my $template = 'admin/users/list';
  my $t = $req->cgi->param('_t');
  $template .= "_$t" if defined($t) && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
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

sub req_edit {
  my ($class, $req, $msg, $errors) = @_;

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
  elsif ($cgi->param('m')) {
    $msg = join("<br />", map escape_html($_), $cgi->param('m'));
  }
  else {
    if (keys %$errors) {
      my %work = %$errors;
      my @msgs = grep defined, delete @work{$cgi->param()};
      push @msgs, values %work;
      $msg = join "<br />", map escape_html($_), @msgs;
    }
    else {
      $msg = '';
    }
  }

  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my $sub_index;
  require BSE::SubscribedUsers;
  my @usersubs = BSE::SubscribedUsers->getBy(userId=>$siteuser->{id});
  my %usersubs = map { $_->{subId}, $_ } @usersubs;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     BSE::Util::Tags->admin(undef, $req->cfg),
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
    );  

  my $template = 'admin/users/edit';
  my $t = $req->cgi->param('_t');
  $template .= "_$t" if defined($t) && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
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
  for my $col (@cols) {
    my $value = $cgi->param($col);
    if ($cfg->entryBool('site users', "require_$col")) {
      if (defined $value && $value eq '') {
	my $disp = $cfg->entry('site users', "display_$col", "\u$col");
	$errors{$col} = "$disp is a required field";
      }
    }
  }

  my $saveemail;
  my $email = $cgi->param('email');
  if (defined $email && $email ne $user->{email}) {
    if (!$email) {
      $errors{email} = "Email is a required field";
    }
    elsif ($email !~ /.\@./) {
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

  if ($cgi->param('checkedsubs')) {
    $class->save_subs($req, $user);
  }

  my $custom = custom_class($cfg);
  $custom->siteusers_changed($cfg);

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
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     BSE::Util::Tags->admin(undef, $req->cfg),
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

  my $template = 'admin/users/add';
  my $t = $req->cgi->param('_t');
  $template .= "_$t" if defined($t) && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
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

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  my %errors;
  my $email = $cgi->param('email');
  if (!defined $email or !length $email) {
    $errors{email} = "Please enter an email address";
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
    
    my $custom = custom_class($cfg);
    $custom->siteusers_changed($cfg);

    my $r = $cgi->param('r');
    unless ($r) {
      $r = $req->url('siteusers', { list => 1, 
				    'm' => "User $user->{userId} added" });
    }
    $r .= "&m=".escape_url($msg) if $msg;
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

1;