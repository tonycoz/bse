package BSE::UserReg;
use strict;
use SiteUsers;
use BSE::Util::Tags qw(tag_error_img);
use BSE::Template;
use Constants qw($SHOP_FROM);
use BSE::Message;
use BSE::SubscriptionTypes;
use BSE::SubscribedUsers;
use BSE::Mail;
use BSE::EmailRequests;
use BSE::Util::SQL qw/now_datetime/;
use DevHelp::HTML;
use Util;

use constant MAX_UNACKED_CONF_MSGS => 3;
use constant MIN_UNACKED_CONF_GAP => 2 * 24 * 60 * 60;

my @donttouch = qw(id userId password email confirmed confirmSecret waitingForConfirmation disabled flags);
my %donttouch = map { $_, $_ } @donttouch;

sub user_tags {
  my ($self, $acts, $session, $user) = @_;

  unless ($user) {
    my $userid = $session->{userid};
    
    if ($userid) {
      $user = SiteUsers->getBy(userId=>$userid);
    }
  }

  return
    (
     ifUser=> 
     sub { 
       if ($_[0]) {
	 return $user->{$_[0]};
       }
       else {
	 return $user;
       }
     },
     user => sub { $user && CGI::escapeHTML($user->{$_[0]}) },
    );
}

sub _refresh_userpage ($$) {
  my ($cfg, $msg) = @_;

  my $url = $cfg->entryErr('site', 'url') . "/cgi-bin/user.pl?userpage=1";
  if (defined $msg) {
    $url .= '&message='.CGI::escape($msg);
  }
  refresh_to($url);
}

sub show_logon {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  if ($nopassword) {
    return $self->nopassword($session, $cgi, $cfg);
  }

  $message ||= $cgi->param('message') || '';
  if (my $msgid = $cgi->param('mid')) {
    my $temp = $cfg->entry("messages", $msgid);
    $message = $temp if $temp;
  }
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     $self->user_tags(\%acts, $session),
     message => sub { CGI::escapeHTML($message) },
    );

  BSE::Template->show_page('user/logon', $cfg, \%acts);
}

sub logon {
  my ($self, $session, $cgi, $cfg) = @_;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  if ($nopassword) {
    return $self->nopassword($session, $cgi, $cfg);
  }
  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $cgi->param('userid')
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(needlogon=>"Please enter a logon name"));
  my $password = $cgi->param('password')
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(needpass=>"Please enter your password"));
  my $user = SiteUsers->getBy(userId => $userid);
  unless ($user && $user->{password} eq $password) {
    return $self->show_logon($session, $cgi, $cfg, 
			     $msgs->(baduserpass=>"Invalid user or password"));
  }
  if ($user->{disabled}) {
    return $self->show_logon($session, $cgi, $cfg,
			     $msgs->(disableduser=>"Account $userid has been disabled"));
  }
  $session->{userid} = $user->{userId};
  $user->{previousLogon} = $user->{lastLogon};
  $user->{lastLogon} = now_datetime;
  $user->save;
  print "Set-Cookie: ",BSE::Session->
    make_cookie($cfg, userid=>$user->{userId}),"\n";

  _got_user_refresh($session, $cgi, $cfg);
}

sub _got_user_refresh {
  my ($session, $cgi, $cfg) = @_;

  my $baseurl = $cfg->entryVar('site', 'url');
  my $securl = $cfg->entryVar('site', 'secureurl');
  my $need_magic = $baseurl ne $securl;
  my $onbase = 1;
  my $debug = $cfg->entryBool('debug', 'logon_cookies', 0);
  if ($need_magic) {
    print STDERR "Logon Cookies Debug\n" if $debug;

    # which host are we on?
    # first get info about the 2 possible hosts
    my ($baseprot, $basehost, $baseport) = 
      $baseurl =~ m!^(\w+)://([\w.-]+)(?::(\d+))?!;
    $baseport ||= $baseprot eq 'http' ? 80 : 443;
    print STDERR "Base: prot: $baseprot  Host: $basehost  Port: $baseport\n"
      if $debug;

    #my ($secprot, $sechost, $secport) = 
    #  $securl =~ m!^(\w+)://([\w.-]+)(?::(\d+))?!;

    # get info about the current host
    my $port = $ENV{SERVER_PORT} || 80;
    my $ishttps = exists $ENV{HTTPS} || exists $ENV{SSL_CIPHER};
    print STDERR "\$ishttps: $ishttps\n" if $debug;
    my $protocol = $ishttps ? 'https' : 'http';

    if (lc $ENV{SERVER_NAME} ne lc $basehost
       || lc $protocol ne $baseprot
       || $baseport != $port) {
      print STDERR "not on base host ('$ENV{SERVER_NAME}' cmp '$basehost' '$protocol cmp '$baseprot'  $baseport cmp $port\n";
      $onbase = 0;
    }
  }
  my $refresh = $cgi->param('r');
  unless ($refresh) {
    if ($session->{userid}) {
      $refresh = "$ENV{SCRIPT_NAME}?userpage=1";
    }
    else {
      $refresh = "$ENV{SCRIPT_NAME}?show_logon=1";
    }
  }
  if ($need_magic) {
    my $url = $onbase ? $securl : $baseurl;
    my $finalbase = $onbase ? $baseurl : $securl;
    $refresh = $finalbase . $refresh unless $refresh =~ /^\w+:/;
    print STDERR "Heading to $url to setcookie\n" if $debug;
    $url .= "$ENV{SCRIPT_NAME}?setcookie=".$session->{_session_id};
    $url .= "&r=".CGI::escape($refresh);
    refresh_to($url);
  }
  else {
    refresh_to($refresh);
  }
}

sub set_cookie {
  my ($self, $session, $cgi, $cfg) = @_;

  my $debug = $cfg->entryBool('debug', 'logon_cookies', 0);
  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $cookie = $cgi->param('setcookie')
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(nocookie=>"No cookie provided"));
  print STDERR "Setting sessionid to $cookie for $ENV{HTTP_HOST}\n";
  my %newsession;
  BSE::Session->change_cookie($session, $cfg, $cookie, \%newsession);
  if (exists $session->{cart} && !exists $newsession{cart}) {
    $newsession{cart} = $session->{cart};
    $newsession{custom} = $session->{custom} if exists $session->{custom};
  }
  my $refresh = $cgi->param('r') 
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(norefresh=>"No refresh provided"));
  my $userid = $newsession{userid};
  if ($userid) {
    my $user = SiteUsers->getBy(userId => $userid);
    print "Set-Cookie: ",BSE::Session->
      make_cookie($cfg, userid=>$userid),"\n";
  }
  else {
    # clear it 
    print "Set-Cookie: ",BSE::Session->
      make_cookie($cfg, userid=> ''),"\n";
 }
  refresh_to($refresh);
}

sub logoff {
  my ($self, $session, $cgi, $cfg) = @_;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  if ($nopassword) {
    return $self->nopassword($session, $cgi, $cfg);
  }

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $session->{userid}
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(notloggedon=>"You aren't logged on"));

  delete $session->{userid};
  print "Set-Cookie: ",BSE::Session->
    make_cookie($cfg, userid=>''),"\n";

  _got_user_refresh($session, $cgi, $cfg);
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

sub tag_if_required {
  my ($cfg, $args) = @_;

  return $cfg->entryBool('site users', "require_$args", 0);
}

sub show_register {
  my ($self, $session, $cgi, $cfg, $message, $errors) = @_;

  my $user_register = $cfg->entryBool('site users', 'user_register', 1);
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  unless ($user_register) {
    if ($nopassword) {
      return $self->show_lost_password($session, $cgi, $cfg,
				       "Registration disabled");
    }
    else {
      return $self->show_logon($session, $cgi, $cfg,
			       "Registration disabled");
    }
  }
  $errors ||= {};
  $message ||= $cgi->param('message');
  if (defined $message) {
    $message = escape_html($message);
  }
  else {
    if (keys %$errors) {
      my @keys = $cgi->param();
      my %errors_copy = %$errors;
      my @errors = grep defined, delete @errors_copy{@keys};
      push @errors, values %errors_copy;
      $message = join("<br />", map escape_html($_), @errors);
    }
    else {
      $message = '';
    }
  }

  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my $sub_index = -1;
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     $self->user_tags(\%acts, $session),
     old => 
     sub {
       my $value = $cgi->param($_[0]);
       defined $value or $value = '';
       CGI::escapeHTML($value);
     },
     message => $message,
     BSE::Util::Tags->make_iterator(\@subs, 'subscription', 'subscriptions',
				   \$sub_index),
     ifSubscribed =>
     [ \&tag_if_subscribed_register, $cgi, $cfg, \@subs, \$sub_index ],
     ifRequired =>
     [ \&tag_if_required, $cfg ],
     error_img => [ \&tag_error_img, $cfg, $errors ],
    );

  BSE::Template->show_page('user/register', $cfg, \%acts);
}

sub _get_user {
  my ($self, $session, $cgi, $cfg, $name) = @_;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  if ($nopassword) {
    my $password;
    $password = $cgi->param($name) if $name;
    $password ||= $cgi->param('p');
    my $uid = $cgi->param('u');
    defined $uid && $uid =~ /^\d+$/ && defined $password
      or do { refresh_to($ENV{SCRIPT}."?nopassword=1"); return };

    my $user = SiteUsers->getByPkey($uid)
      or do { refresh_to($ENV{SCRIPT}."?nopassword=1"); return };

    $user->{password} eq $password
      or do { refresh_to($ENV{SCRIPT}."?nopassword=1"); return };
    
    return $user;
  }
  else {
    if ($cfg->entryBool('custom', 'user_auth')) {
      my $custom = Util::custom_class($cfg);

      return $custom->siteuser_auth($session, $cgi, $cfg);
    }
    else {
      my $userid = $session->{userid}
	or do { $self->show_logon($session, $cgi, $cfg); return };
      my $user = SiteUsers->getBy(userId=>$userid)
	or do { $self->show_logon($session, $cgi, $cfg); return };
      $user->{disabled}
	and do { $self->show_logon($session, $cgi, $cfg, "Account disabled"); return };
      
      return $user;
    }
  }
}

sub show_opts {
  my ($self, $session, $cgi, $cfg, $message, $errors) = @_;

  my $user = $self->_get_user($session, $cgi, $cfg, 'show_opts')
    or return;
  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my @usersubs = BSE::SubscribedUsers->getBy(userId=>$user->{id});
  my %usersubs = map { $_->{subId}, $_ } @usersubs;
  
  my $sub_index;
  $errors ||= {};
  $message ||= $cgi->param('message');
  if (defined $message) {
    $message = escape_html($message);
  }
  else {
    if (keys %$errors) {
      my @keys = $cgi->param();
      my %errors_copy = %$errors;
      my @errors = grep defined, delete @errors_copy{@keys};
      push @errors, values %errors_copy;
      $message = join("<br />", map escape_html($_), @errors);
    }
    else {
      $message = '';
    }
  }

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     $self->user_tags(\%acts, $session, $user),
     last => 
     sub {
       my $value = $cgi->param($_[0]);
       defined $value or $value = $user->{$_[0]};
       defined $value or $value = '';
       CGI::escapeHTML($value);
     },
     message => $message,
     BSE::Util::Tags->make_iterator(\@subs, 'subscription', 'subscriptions',
				    \$sub_index),
     ifSubscribed=>sub { $usersubs{$subs[$sub_index]{id}} },
     ifAnySubs => sub { @usersubs },
     ifRequired =>
     [ \&tag_if_required, $cfg ],
     error_img => [ \&tag_error_img, $cfg, $errors ],
    );

  my $base = 'user/options';
  my $template = $base;

  my $t = $cgi->param('_t');
  if ($t && $t =~ /^\w+$/) {
    $template .= "_$t";
  }

  BSE::Template->show_page($template, $cfg, \%acts, $base);
}

sub _checkemail {
  my ($user, $errors, $email, $cgi, $msgs, $nopassword) = @_;

  if (!$email) {
    $errors->{email} = $msgs->(optsnoemail => "Please enter an email address");
  }
  elsif ($email !~  /.@./) {
    $errors->{email} = $msgs->(optsbademail=>
			       "Please enter a valid email address");
  }
  else {
    if ($nopassword && $email ne $user->{email}) {
      my $conf_email = $cgi->param('confirmemail');
      if ($conf_email) {
	if ($conf_email eq $email) {
	  my $other = SiteUsers->getBy(userId=>$email);
	  if ($other) {
	    $errors->{email} = 
	      $msgs->(optsdupemail =>
		      "That email address is already in use");
	  }
	}
	else {
	  $errors->{confirmemail} = 
	    $msgs->(optsconfemailnw=>
		    "Confirmation email address doesn't match email address");
	}
      }
      else {
	$errors->{confirmemail} = 
	  $msgs->(optsnoconfemail=> "Please enter a confirmation email address");
      }
      
    }
  }
  if (!$errors->{email}) {
    my $checkemail = _generic_email($email);
    require 'BSE/EmailBlacklist.pm';
    my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);
    if ($blackentry) {
      $errors->{email} = 
	$msgs->(optsblackemail => 
		"Email $email is blacklisted: $blackentry->{why}",
		$email, $blackentry->{why});
    }
  }
}

sub saveopts {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');

  my $user = $self->_get_user($session, $cgi, $cfg)
    or return;
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  my %errors;
  my $newpass;
  unless ($nopassword) {
    my $oldpass = $cgi->param('old_password');
    $newpass = $cgi->param('password');
    my $confirm = $cgi->param('confirm_password');
    
    if (defined $newpass && length $newpass) {
      if ($oldpass) {
	if ($oldpass ne $user->{password}) {
	  sleep 5; # yeah, it's ugly
	  $errors{old_password} = $msgs->(optsbadold=>"You need to enter your old password to change your password")
	}
	else {
	  my $min_pass_length = $cfg->entry('basic', 'minpassword') || 4;
	  my $error;
	  if (length $newpass < $min_pass_length) {
	    $errors{password} = $msgs->(optspasslen=>
					"The password must be at least $min_pass_length characters",
					$min_pass_length);
	  }
	  elsif (!defined $confirm || length $confirm == 0) {
	    $errors{confirm_password} = $msgs->(optsconfpass=>"Please enter a confirmation password");
	  }
	  elsif ($newpass ne $confirm) {
	    $errors{confirm_password} = $msgs->(optsconfmismatch=>"The confirmation password is different from the password");
	  }
	}
      }
      else {
	$errors{old_password} = 
	  $msgs->(optsoldpass=>"You need to enter your old password to change your password")
      }
    }
  }
  my $email = $cgi->param('email');
  my $saveemail;
  if (defined $email) {
    ++$saveemail;
    _checkemail($user, \%errors, $email, $cgi, $msgs, $nopassword);
  }

      
  my @cols = grep !$donttouch{$_}, SiteUser->columns;
  for my $col (@cols) {
    my $value = $cgi->param($col);
    if ($cfg->entryBool('site users', "require_$col")) {
      if (defined $value && $value eq '') {
	my $disp = $cfg->entry('site users', "display_$col", "\u$col");
	$errors{$col} = $msgs->("optsrequired" => 
				"$disp is a required field", $col, $disp);
      }
    }
  }
  keys %errors
    and return $self->show_opts($session, $cgi, $cfg, undef, \%errors);
  my $newemail;
  if ($saveemail && $email ne $user->{email}) {
    $user->{confirmed} = 0;
    $user->{confirmSecret} = '';
    $user->{email} = $email;
    $user->{userId} = $email if $nopassword;
    ++$newemail;
  }
  $user->{password} = $newpass if !$nopassword && $newpass;
  
  for my $col (@cols) {
    my $value = $cgi->param($col);
    if (defined $value) {
      $user->{$col} = $value;
    }
  }

  $user->{textOnlyMail} = 0 
    if $cgi->param('saveTextOnlyMail') && !defined $cgi->param('textOnlyMail');
  $user->{keepAddress} = 0 
    if $cgi->param('saveKeepAddress') && !defined $cgi->param('keepAddress');
  $user->save;

  # subscriptions
  my $subs;
  if ($cgi->param('saveSubscriptions')) {
    $subs = $self->_save_subs($user, $session, $cfg, $cgi);
  }
  if ($nopassword) {
    return $self->send_conf_request($session, $cgi, $cfg, $user)
      if $newemail;
  }
  else {
    $subs = () = $user->subscriptions unless defined $subs;
    return $self->send_conf_request($session, $cgi, $cfg, $user)
      if $subs && !$user->{confirmed};
  }

  my $url = $cgi->param('r');
  unless ($url) {
    $url = $cfg->entryErr('site', 'url') . "$ENV{SCRIPT_NAME}?userpage=1";
    if ($nopassword) {
      $url =~ s/1$/$user->{password}/;
      $url .= "&u=$user->{id}";
    }
    my $t = $cgi->param('t');
    if ($t && $t =~ /^\w+$/) {
      $url .= "&_t=$t";
    }
  }

  my $custom = Util::custom_class($cfg);
  $custom->siteusers_changed($cfg);

  refresh_to($url);
}

# returns true if the caller needs to send output
sub _save_subs {
  my ($self, $user, $session, $cfg, $cgi) = @_;

  my @subids = $cgi->param('subscription');
  $user->removeSubscriptions;
  if (@subids) {
    my @usersubs;
    my @subs;
    my @cols = BSE::SubscribedUser->columns;
    shift @cols; # don't set id
    my $found = 0;
    for my $subid (@subids) {
      $subid =~ /^\d+$/ or next;
      my $sub = BSE::SubscriptionTypes->getByPkey($subid)
	or next;
      ++$found;
      my %usersub;
      $usersub{subId} = $subid;
      $usersub{userId} = $user->{id};

      push(@usersubs, BSE::SubscribedUsers->add(@usersub{@cols}));
      push(@subs, $sub);
    }
    return $found;
  }
  return 0;
}

sub register {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');

  my $user_register = $cfg->entryBool('site users', 'user_register', 1);
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  unless ($user_register) {
    my $msg = $msgs->(regdisabled => "Registration disabled");
    if ($nopassword) {
      return $self->show_lost_password($session, $cgi, $cfg, $msg);
    }
    else {
      return $self->show_logon($session, $cgi, $cfg, $msg);
    }
  }

  my %user;
  my @cols = SiteUser->columns;
  shift @cols;
  for my $field (@cols) {
    $user{$field} = '';
  }

  my %errors;
  my $email = $cgi->param('email');
  if (!defined $email or !length $email) {
    $errors{email} = $msgs->(regnoemail => "Please enter an email address");
    $email = ''; # prevent undefined value warnings later
  }
  elsif ($email !~ /.\@./) {
    $errors{email} = $msgs->(regbademail => "Please enter a valid email address");
  }
  if ($nopassword) {
    my $confemail = $cgi->param('confirmemail');
    if (!defined $confemail or !length $confemail) {
      $errors{confirmemail} = $msgs->(regnoconfemail => "Please enter a confirmation email address");
    }
    elsif ($email ne $confemail) {
      $errors{confirmemail} = $msgs->(regbadconfemail => "Confirmation email should match the Email Address");
    }
    my $user = SiteUsers->getBy(userId=>$email);
    if ($user) {
      $errors{email} = $msgs->(regemailexists=>
				"Sorry, email $email already exists as a user",
				$email);
    }
    $user{userId} = $email;
    $user{password} = '';
  }
  else {
    my $min_pass_length = $cfg->entry('basic', 'minpassword') || 4;
    my $userid = $cgi->param('userid');
    if (!defined $userid || length $userid == 0) {
      $errors{userid} = $msgs->(reguser=>"Please enter a userid");
    }
    my $pass = $cgi->param('password');
    my $pass2 = $cgi->param('confirm_password');
    if (!defined $pass || length $pass == 0) {
      $errors{password} = $msgs->(regpass=>"Please enter a password");
    }
    elsif (length $pass < $min_pass_length) {
      $errors{password} = $msgs->(regpasslen=>"The password must be at least $min_pass_length characters");
    }
    elsif (!defined $pass2 || length $pass2 == 0) {
      $errors{confirm_password} = 
	$msgs->(regconfpass=>"Please enter a confirmation password");
    }
    elsif ($pass ne $pass2) {
      $errors{confirm_password} = 
	$msgs->(regconfmismatch=>"The confirmation password is different from the password");
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
      $errors{userid} = $msgs->(regexists=>
				"Sorry, user $userid already exists",
				$userid);
    }
    $user{userId} = $userid;
    $user{password} = $pass;
  }

  unless ($errors{email}) {
    my $checkemail = _generic_email($email);
    require 'BSE/EmailBlacklist.pm';
    my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);
    if ($blackentry) {
      $errors{email} = $msgs->(regblackemail => 
			       "Email $email is blacklisted: $blackentry->{why}",
			       $email, $blackentry->{why});
    }
  }

  my @mod_cols = grep !$donttouch{$_}, @cols;
  for my $col (@mod_cols) {
    my $value = $cgi->param($col);
    if ($cfg->entryBool('site users', "require_$col")) {
      unless (defined $value && $value ne '') {
	my $disp = $cfg->entry('site users', "display_$col", "\u$col");
	
	$errors{$col} = $msgs->(regrequired => "$disp is a required field", 
				$col, $disp);
      }
    }
    if (defined $value) {
      $user{$col} = $value;
    }
  }
  if (keys %errors) {
    return $self->show_register($session, $cgi, $cfg, undef, \%errors);
  }

  $user{email} = $email;
  $user{lastLogon} = $user{whenRegistered} = 
    $user{previousLogon} = now_datetime;
  $user{keepAddress} = 0;
  $user{wantLetter} = 0;
  if ($nopassword) {
    use BSE::Util::Secure qw/make_secret/;
    $user{password} = make_secret($cfg);
  }

  my $user;
  eval {
    $user = SiteUsers->add(@user{@cols});
  };
  if ($user) {
    print "Set-Cookie: ",BSE::Session->
      make_cookie($cfg, userid=>$user->{userId}),"\n";
    $session->{userid} = $user->{userId} unless $nopassword;
    my $subs = $self->_save_subs($user, $session, $cfg, $cgi);
    if ($nopassword) {
      return $self->send_conf_request($session, $cgi, $cfg, $user);
    }
    elsif ($subs) {
      return if $self->send_conf_request($session, $cgi, $cfg, $user, 1);
    }
    use Util qw/refresh_to/;
    
    _got_user_refresh($session, $cgi, $cfg);

    my $custom = Util::custom_class($cfg);
    $custom->siteusers_changed($cfg);
  }
  else {
    $self->show_register($session, $cgi, $cfg,
			 $msgs->(regdberr=>
				 "Database error $@"));
  }
}

sub userpage {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  my $user = $self->_get_user($session, $cgi, $cfg, 'userpage')
    or return;
  require 'Orders.pm';
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate}
			|| $b->{id} <=> $a->{id} }
    Orders->getBy(userId=>$user->{userId});
  $message ||= $cgi->param('message') || '';

  my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  my $must_be_filled = $cfg->entryBool('downloads', 'must_be_filled', 0);

  my $order_index;
  my $item_index;
  my @items;
  my %acts;
  my $product;
  my @files;
  my $file_index;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     $self->user_tags(\%acts, $session, $user),
     message => sub { CGI::escapeHTML($message) },
     BSE::Util::Tags->make_iterator(\@orders, 'order', 'orders', 
				    \$order_index),
     BSE::Util::Tags->
     make_dependent_iterator(\$order_index,
			     sub {
			       require 'OrderItems.pm';
			       @items = OrderItems->
				 getBy(orderId=>$orders[$_[0]]{id});
			     },
			     'item', 'items', \$item_index),
     BSE::Util::Tags->
     make_dependent_iterator(\$order_index,
			     sub {
			       @files = BSE::DB->query
				 (orderFiles=>$orders[$_[0]]{id});
			     },
			     'orderfile', 'orderfiles', \$file_index),
     product =>
     sub {
       require 'Products.pm';
       $product = Products->getByPkey($items[$item_index]{productId})
	 unless $product && $product->{id} == $items[$item_index]{productId};
       CGI::escapeHTML($product->{$_[0]});
     },
     BSE::Util::Tags->
     make_multidependent_iterator
     ([ \$item_index, \$order_index],
      sub {
	require 'ArticleFiles.pm';
	@files = sort { $b->{displayOrder} <=> $a->{displayOrder} }
	  ArticleFiles->getBy(articleId=>$items[$item_index]{productId});
      },
      'prodfile', 'prodfiles', \$file_index),
     ifFileAvail =>
     sub {
       if ($file_index >= 0 && $file_index < @files) {
	 return 1 if !$files[$file_index]{forSale};
       }
       return 0 if $must_be_paid && !$orders[$order_index]{paidFor};
       return 0 if $must_be_filled && !$orders[$order_index]{filled};
       return 1;
     },
    );
  my $base_template = 'user/userpage';
  my $template = $base_template;
  my $t = $cgi->param('_t');
  if (defined $t && $t =~ /^\w+$/) {
    $template = $template . '_' . $t;
  }
  BSE::Template->show_page($template, $cfg, \%acts, $base_template);
}

sub download {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $user = $self->_get_user($session, $cgi, $cfg, 'show_opts')
    or return;

  my $orderid = $cgi->param('order')
    or return _refresh_userpage($cfg, $msgs->('noorderid', "No order id supplied"));
  require 'Orders.pm';
  my $order = Orders->getByPkey($orderid)
    or return _refresh_userpage($cfg, $msgs->('nosuchorder',
					"No such orderd $orderid", $orderid));
  unless (length $order->{userId}
	  && $order->{userId} eq $user->{userId}) {
    return _refresh_userpage($cfg, $msgs->("notyourorder",
				     "Order $orderid isn't yours", $orderid));
  }
  my $itemid = $cgi->param('item')
    or return _refresh_userpage($cfg, $msgs->('noitemid', "No item id supplied"));
  require 'OrderItems.pm';
  my ($item) = grep $_->{id} == $itemid,
  OrderItems->getBy(orderId=>$order->{id})
    or return _refresh_userpage($cfg, $msgs->(notinorder=>"Not part of that order"));
  require 'ArticleFiles.pm';
  my @files = ArticleFiles->getBy(articleId=>$item->{productId})
    or return _refresh_userpage($cfg, $msgs->(nofilesonline=>"No files in this line"));
  my $fileid = $cgi->param('file')
    or return _refresh_userpage($cfg, $msgs->(nofileid=>"No file id supplied"));
  my ($file) = grep $_->{id} == $fileid, @files
    or return _refresh_userpage($cfg, $msgs->(nosuchfile=>"No such file in that line item"));
  
  my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  my $must_be_filled = $cfg->entryBool('downloads', 'must_be_filled', 0);
  if ($must_be_paid && !$order->{paidFor} && $file->{forSale}) {
    return _refresh_userpage($cfg, $msgs->("paidfor", 
				     "Order not marked as paid for"));
  }
  if ($must_be_filled && !$order->{filled} && $file->{forSale}) {
    return _refresh_userpage($cfg, $msgs->("filled", 
				     "Order not marked as filled"));
  }
  
  my $filebase = $cfg->entryVar('paths', 'downloads');
  open FILE, "< $filebase/$file->{filename}"
    or return _refresh_userpage($cfg, 
	       $msgs->(openfile =>
		       "Sorry, cannot open that file.  Contact the webmaster.",
		       $!));
  binmode FILE;
  binmode STDOUT;
  print "Content-Length: $file->{sizeInBytes}\r\n";
  if ($file->{download}) {
    print qq/Content-Disposition: attachment; filename=$file->{displayName}\r\n/;
    print "Content-Type: application/octet-stream\r\n";
  }
  else {
    print "Content-Type: $file->{contentType}\r\n";
  }
  print "\r\n";
  $|=1;
  my $data;
  while (read(FILE, $data, 8192)) {
    print $data;
  }
  close FILE;
}

sub download_file {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $session->{userid};
  my $user;
  if ($userid) {
    $user = SiteUsers->getBy(userId=>$userid);
  }
  my $fileid = $cgi->param('file')
    or return $self->show_logon($session, $cgi, $cfg, 
			 $msgs->('nofileid', "No file id supplied"));
  require 'ArticleFiles.pm';
  my $file = ArticleFiles->getByPkey($fileid)
    or return $self->show_logon($session, $cgi, $cfg,
			 $msgs->('nosuchfile', "No such download"));
  $cfg->entryBool('downloads', 'require_logon', 0) && !$user
    and return $self->show_logon($session, $cgi, $cfg,
			  $msgs->('downloadlogonall', 
				  "You must be logged on to download files"));
    
  $file->{requireUser} && !$user
    and return $self->show_logon($session, $cgi, $cfg,
			  $msgs->('downloadlogon',
				  "You must be logged on to download this file"));
  $file->{forSale}
    and return $self->show_logon($session, $cgi, $cfg,
			  $msgs->('downloadforsale',
				  "This file can only be downloaded as part of an order"));
  
  my $filebase = $cfg->entryVar('paths', 'downloads');
  open FILE, "< $filebase/$file->{filename}"
    or return $self->show_logon($session, $cgi, $cfg, 
	       $msgs->(openfile =>
		       "Sorry, cannot open that file.  Contact the webmaster.",
		       $!));
  binmode FILE;
  binmode STDOUT;
  print "Content-Length: $file->{sizeInBytes}\r\n";
  if ($file->{download}) {
    print qq/Content-Disposition: attachment; filename=$file->{displayName}\r\n/;
    print "Content-Type: application/octet-stream\r\n";
  }
  else {
    print "Content-Type: $file->{contentType}\r\n";
  }
  print "\r\n";
  $|=1;
  my $data;
  while (read(FILE, $data, 8192)) {
    print $data;
  }
  close FILE;
}

sub show_lost_password {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  $message ||= $cgi->param('message') || '';
  $message = escape_html($message);
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     message => $message,
    );
  BSE::Template->show_page('user/lostpassword', $cfg, \%acts);
}

sub lost_password {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $cgi->param('userid');
  defined $userid && length $userid
    or return $self->show_lost_password($session, $cgi, $cfg,
					$msgs->(lostnouserid=>
						"Please enter a logon id"));
  
  my $user = SiteUsers->getBy(userId=>$userid)
    or return $self->show_lost_password($session, $cgi, $cfg,
					$msgs->(lostnosuch=>
						"No such userid", $userid));

  require 'BSE/Mail.pm';

  my $mail = BSE::Mail->new(cfg=>$cfg);

  my %mailacts;
  %mailacts =
    (
     user => sub { $user->{$_[0]} },
     host => sub { $ENV{REMOTE_ADDR} },
     site => sub { $cfg->entryErr('site', 'url') },
    );
  my $body = BSE::Template->get_page('user/lostpwdemail', $cfg, \%mailacts);
  my $from = $cfg->entry('confirmations', 'from') || 
    $cfg->entry('basic', 'emailfrom') || $SHOP_FROM;
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  my $subject = $cfg->entry('basic', 'lostpasswordsubject') 
    || ($nopassword ? "Your options" : "Your password");
  $mail->send(from=>$from, to=>$user->{email}, subject=>$subject,
	      body=>$body)
    or return $self->show_lost_password($session, $cgi, $cfg,
					$msgs->(lostmailerror=>
						"Email error:".$mail->errstr,
						$mail->errstr));
  my %acts;
  %acts = 
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     user => sub { CGI::escapeHTML($user->{$_[0]}) },
    );
  BSE::Template->show_page('user/lostemailsent', $cfg, \%acts);
}

sub subinfo {
  my ($self, $session, $cgi, $cfg) = @_;

  my $id = $cgi->param('id')
    or return $self->show_opts($session, $cgi, $cfg, "No subscription id parameter");
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return $self->show_opts($session, $cgi, $cfg, "Unknown subscription id");
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     subscription=>sub { CGI::escapeHTML($sub->{$_[0]}) },
    );
  BSE::Template->show_page('user/subdetail', $cfg, \%acts);
}

sub nopassword {
  my ($self, $session, $cgi, $cfg) = @_;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
    );
  BSE::Template->show_page('user/nopassword', $cfg, \%acts);
}

sub blacklist {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $email = $cgi->param('blacklist')
    or return $self->show_logon($session, $cgi, $cfg,
				$msgs->(blnoemail=>"No email supplied"));
  my $genemail = _generic_email($email);

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     email => sub { CGI::escapeHTML($email) },
    );
  require BSE::EmailBlacklist;
  my $black = BSE::EmailBlacklist->getEntry($genemail);
  if ($black) {
    BSE::Template->show_page('user/alreadyblacklisted', $cfg, \%acts);
    return;
  }
  my %black;
  my @cols = BSE::EmailBlackEntry->columns;
  shift @cols;
  $black{email} = $genemail;
  $black{why} = "Web request from $ENV{REMOTE_ADDR}";
  $black = BSE::EmailBlacklist->add(@black{@cols});
  BSE::Template->show_page('user/blacklistdone', $cfg, \%acts);
}

sub confirm {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $secret = $cgi->param('confirm')
    or return $self->show_logon($session, $cgi, $cfg,
				$msgs->(confnosecret=>"No secret supplied for confirmation"));
  my $userid = $cgi->param('u')
    or return $self->show_logon($session, $cgi, $cfg,
				$msgs->(confnouser=>"No user supplied for confirmation"));
  if ($userid + 0 != $userid || $userid < 1) {
    return $self->show_logon($session, $cgi, $cfg,
			     $msgs->(confbaduser=>"Invalid or unknown user supplied for confirmation"));
  }
  my $user = SiteUsers->getByPkey($userid)
    or return $self->show_logon($session, $cgi, $cfg,
			     $msgs->(confbaduser=>"Invalid or unknown user supplied for confirmation"));
  unless ($secret eq $user->{confirmSecret}) {
    return $self->show_logon($session, $cgi, $cfg, 
			     $msgs->(confbadsecret=>"Sorry, the confirmation secret does not match"));
  }

  $user->{confirmed} = 1;
  # I used to reset this, but it doesn't really make sense
  # $user->{confirmSecret} = '';
  $user->save;
  my $genEmail = _generic_email($user->{email});
  my $request = BSE::EmailRequests->getBy(genEmail=>$genEmail);
  $request and $request->remove();
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     user=>sub { CGI::escapeHTML($user->{$_[0]}) },
    );
  BSE::Template->show_page('user/confirmed', $cfg, \%acts);
}

sub _generic_email {
#  SiteUser->generic_email(shift);
  my ($checkemail) = @_;

  # Build a generic form for the email - since an attacker could
  # include comments or extra spaces or a bunch of other stuff.
  # this isn't strictly correct, but it's good enough
  1 while $checkemail =~ s/\([^)]\)//g;
  if ($checkemail =~ /<([^>]+)>/) {
    $checkemail = $1;
  }
  $checkemail = lc $checkemail;
  $checkemail =~ s/\s+//g;

  $checkemail;
}

# returns non-zero iff a page was generated
sub send_conf_request {
  my ($self, $session, $cgi, $cfg, $user, $suppress_success) = @_;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  # check for existing in-progress confirmations
  my $checkemail = _generic_email($user->{email});

  # check the blacklist
  require 'BSE/EmailBlacklist.pm';

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     user=>sub { CGI::escapeHTML($user->{$_[0]}) },
    );
  
  # check that the from address has been configured
  my $from = $cfg->entry('confirmations', 'from') || 
    $cfg->entry('basic', 'emailfrom')|| $SHOP_FROM;
  unless ($from) {
    $acts{mailerror} = sub { escape_html("Configuration Error: The confirmations from address has not been configured") };
    BSE::Template->show_page('user/email_conferror', $cfg, \%acts);
    return 1;
  }

  my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);

  if ($blackentry) {
    $acts{black} = sub { CGI::escapeHTML($blackentry->{$_[0]}) },
    BSE::Template->show_page('user/blacklisted', $cfg, \%acts);
    return 1;
  }
  
  unless ($user->{confirmSecret}) {
    use BSE::Util::Secure qw/make_secret/;
    # print STDERR "Generating secret\n";
    $user->{confirmSecret} = make_secret($cfg);
    $user->save;
  }

  # check for existing confirmations
  my $confirm = BSE::EmailRequests->getBy(genEmail=>$checkemail);
  if ($confirm) {
    $acts{confirm} = sub { CGI::escapeHTML($confirm->{$_[0]}) };
    my $too_many = $confirm->{unackedConfMsgs} >= MAX_UNACKED_CONF_MSGS;
    $acts{ifTooMany} = sub { $too_many };
    use BSE::Util::SQL qw/sql_datetime_to_epoch/;
    my $lastSentEpoch = sql_datetime_to_epoch($confirm->{lastConfSent});
    my $too_soon = $lastSentEpoch + MIN_UNACKED_CONF_GAP > time;
    $acts{ifTooSoon} = sub { $too_soon };
    # check how many
    if ($too_many) {
      BSE::Template->show_page('user/toomany', $cfg, \%acts);
      return 1;
    }
    if ($too_soon) {
      BSE::Template->show_page('user/toosoon', $cfg, \%acts);
      return 1;
    }
  }
  else {
    my %confirm;
    my @cols = BSE::EmailRequest->columns;
    shift @cols;
    $confirm{email} = $user->{email};
    $confirm{genEmail} = $checkemail;
    # prevents silliness on error
    use BSE::Util::SQL qw(sql_datetime);
    $confirm{lastConfSent} = sql_datetime(time - MIN_UNACKED_CONF_GAP);
    $confirm{unackedConfMsgs} = 0;
    $confirm = BSE::EmailRequests->add(@confirm{@cols});
  }

  # ok, now we can send the confirmation request
  my %confacts;
  %confacts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     user => sub { $user->{$_[0]} },
     confirm => sub { $confirm->{$_[0]} },
     remote_addr => sub { $ENV{REMOTE_ADDR} },
    );
  my $email_template = 
    $nopassword ? 'user/email_confirm_nop' : 'user/email_confirm';
  my $body = BSE::Template->get_page($email_template, $cfg, \%confacts);
  
  my $mail = BSE::Mail->new(cfg=>$cfg);
  my $subject = $cfg->entry('confirmations', 'subject') 
    || 'Subscription Confirmation';
  unless ($mail->send(from=>$from, to=>$user->{email}, subject=>$subject,
		      body=>$body)) {
    # a problem sending the mail
    $acts{mailerror} = sub { CGI::escapeHTML($mail->errstr) };
    BSE::Template->show_page('user/email_conferror', $cfg, \%acts);
    return;
  }
  ++$confirm->{unackedConfMsgs};
  $confirm->{lastConfSent} = now_datetime;
  $confirm->save;
  return 0 if $suppress_success;
  BSE::Template->show_page($nopassword ? 'user/confsent_nop' : 'user/confsent', $cfg, \%acts);

  return 1;
}

sub unsub {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $secret = $cgi->param('unsub')
    or return $self->show_logon($session, $cgi, $cfg,
				$msgs->(unsubnosecret=>"No secret supplied for unsubscribe"));
  my $userid = $cgi->param('u')
    or return $self->show_logon($session, $cgi, $cfg,
				$msgs->(unsubnouser=>"No user supplied for unsubscribe"));
  if ($userid + 0 != $userid || $userid < 1) {
    return $self->show_logon($session, $cgi, $cfg,
			     $msgs->(unsubbaduser=>"Invalid or unknown user supplied for unsubscribe"));
  }
  my $user = SiteUsers->getByPkey($userid)
    or return $self->show_logon($session, $cgi, $cfg,
			     $msgs->(unsubbaduser=>"Invalid or unknown user supplied for unsubscribe"));
  unless ($secret eq $user->{confirmSecret}) {
    return $self->show_logon($session, $cgi, $cfg, 
			     $msgs->(unsubbadsecret=>"Sorry, the ubsubscribe secret does not match"));
  }
  
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     user => sub { CGI::escapeHTML($user->{$_[0]}) },
    );
  my $subid = $cgi->param('s');
  my $sub;
  if ($subid eq 'all') {
    $user->removeSubscriptions();
    BSE::Template->show_page('user/unsuball', $cfg, \%acts);
  }
  elsif (0+$subid eq $subid 
	 and $sub = BSE::SubscriptionTypes->getByPkey($subid)) {
    $acts{subscription} = sub { CGI::escapeHTML($sub->{$_[0]}) };
    $user->removeSubscription($subid);
    BSE::Template->show_page('user/unsubone', $cfg, \%acts);
  }
  else {
    BSE::Template->show_page('user/cantunsub', $cfg, \%acts);
  }
}

1;
