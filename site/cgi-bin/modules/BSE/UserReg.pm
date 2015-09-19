package BSE::UserReg;
use strict;
use base qw(BSE::UI::SiteuserCommon BSE::UI::Dispatch);
use BSE::TB::SiteUsers;
use BSE::Util::Tags qw(tag_error_img tag_hash tag_hash_plain tag_article);
use BSE::Template;
use Constants qw($SHOP_FROM);
use BSE::Message;
use BSE::SubscriptionTypes;
use BSE::SubscribedUsers;
use BSE::Mail;
use BSE::EmailRequests;
use BSE::Util::SQL qw/now_datetime/;
use BSE::Util::HTML;
use BSE::CfgInfo qw(custom_class);
use BSE::WebUtil qw/refresh_to/;
use BSE::Util::Iterate;
use base 'BSE::UI::UserCommon';
use Carp qw(confess);

our $VERSION = "1.038";

use constant MAX_UNACKED_CONF_MSGS => 3;
use constant MIN_UNACKED_CONF_GAP => 2 * 24 * 60 * 60;

=head1 NAME

BSE::UserReg - member (site user) registration and handling

=head1 SYNOPSIS

  /cgi-bin/user.pl?...

=head1 DESCRIPTION

BSE::UserReg is the user interface handler for user.pl.

=head1 TARGETS

=over

=cut

my %actions =
  (
   show_logon => 'show_logon',
   show_register => 'show_register',
   register => 'register',
   show_opts => 'show_opts',
   saveopts=>'saveopts',
   logon => 'logon',
   logoff => 'logoff',
   userpage=>'userpage',
   download=>'download',
   download_file=>'download_file',
   show_lost_password => 'show_lost_password',
   lost_password => 'lost_password',
   lost => 1,
   lost_save => 1,
   subinfo => 'subinfo',
   blacklist => 'blacklist',
   confirm => 'confirm',
   unsub => 'unsub',
   setcookie => 'set_cookie',
   nopassword => 'nopassword',
   image => 'req_image',
   orderdetail => 'req_orderdetail',
   orderdetaila => 'req_orderdetaila',
   oda => 1,
   wishlist => 'req_wishlist',
   downufile => 'req_downufile',
   file_metadata => "req_file_metadata",
   file_cmetadata => "req_file_cmetadata",
  );

sub actions { \%actions }

sub action_prefix { '' }

sub default_action { 'userpage' }

my @donttouch = qw(id userId password email confirmed confirmSecret waitingForConfirmation disabled flags affiliate_name previousLogon);
my %donttouch = map { $_, $_ } @donttouch;

sub _refresh_userpage ($$) {
  my ($cfg, $msg) = @_;

  my $url = $cfg->entryErr('site', 'url') . "/cgi-bin/user.pl?userpage=1";
  if (defined $msg) {
    $url .= '&m='.escape_uri($msg);
  }
  refresh_to($url);
}

# returns true if the userid cookie should be created
sub _should_make_user_cookie {
  return BSE::Cfg->single->entry("basic", "make_userid_cookie", 1);
}

sub _send_user_cookie {
  my ($self, $user) = @_;

  $self->_should_make_user_cookie or return;

  my $value = $user ? $user->userId : "";

  BSE::Session->send_cookie
      (BSE::Session->make_cookie(BSE::Cfg->single, userid => $value));
}

=item show_logon

Display the logon page.

Tags: standard dynamic tags and the following:

=over

=item *

C<message> - HTML encoded error message text

=item *

C<error_img> - field error indicators.

=back

Template: F<user/logon>

=cut

sub req_show_logon {
  my ($self, $req, $message) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  if ($nopassword) {
    return $self->req_nopassword($req);
  }

  $message ||= $cgi->param('message') || '';
  if (my $msgid = $cgi->param('mid')) {
    my $temp = $cfg->entry("messages", $msgid);
    $message = $temp if $temp;
  }
  my $errors;
  if (ref $message) {
    $errors = $message;
    $message = $req->message($errors);
  }
  elsif ($message) {
    $message = escape_html($message);
    $errors = {};
  }
  else {
    $message = $req->message();
  }
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     message => $message,
     error_img => [ \&tag_error_img, $cfg, $errors ],
    );

  return $req->response('user/logon', \%acts);
}

my %logon_fields =
  (
   userid =>
   {
    description => "Logon name",
    rules => "required",
   },
   password =>
   {
    description => "Password",
    rules => "required",
   },
  );

=item logon

Process a logon request.

Parameters:

=over

=item *

C<userid> - the user's logon

=item *

C<password> - the user's password.

=back

On success, redirect to the L</userpage>.

On failure, re-display the L</logon> form.

=cut

sub req_logon {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  if ($nopassword) {
    return $self->req_nopassword($req);
  }
  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my %errors;
  $req->validate(fields => \%logon_fields,
		 errors => \%errors,
		 section => "Logon Fields");
  my $user;
  my $userid = $cgi->param("userid");
  my $password = $cgi->param("password");
  unless (keys %errors) {
    $user = BSE::TB::SiteUsers->getBy(userId => $userid);
    if ($req->ip_locked_out("S")) {
      $errors{_} = "msg:bse/user/iplockout:".$req->ip_address;
    }
    elsif ($user && $user->locked_out) {
      $errors{_} = "msg:bse/user/userlockout";
    }
    else {
      my $error = "INVALID";
      unless ($user && $user->check_password($password, \$error)) {
	if ($error eq "INVALID") {
	  $errors{_} = $msgs->(baduserpass=>"Invalid username or password");
	  $req->audit
	    (
	     object => $user,
	     component => "siteuser:logon:invalid",
	     actor => "S",
	     level => "warning",
	     msg => "Site User logon attempt failed",
	    );
	  BSE::TB::SiteUser->check_lockouts
	    (
	     request => $req,
	     user => $user,
	    );
	}
	else {
	  $errors{_} = $msgs->(passwordload => "Error loading password module");
	}
      }
    }
  }
  if (!keys %errors && $user->{disabled}) {
    $errors{_} = $msgs->(disableduser=>"Account $userid has been disabled");
  }

  keys %errors
    and return $self->req_show_logon($req, \%errors);

  my %fields = $user->valid_fields($cfg);
  my $custom = custom_class($cfg);
  
  for my $field ($custom->siteuser_edit_required($req, $user)) {
    $fields{$field}{required} = 1;
  }
  my %rules = $user->valid_rules($cfg);

  $req->validate_hash(data => $user,
		      errors => \%errors,
		      fields => \%fields,
		      rules => \%rules,
		      section => 'site user validation');
  _validate_affiliate_name($cfg, $user->{affiliate_name}, \%errors, $msgs, $user);
  if (keys %errors) {
    delete $session->{userid};
    $session->{partial_logon} = $user->id;
    return $self->req_show_opts($req, undef, \%errors);
  }

  $user->{previousLogon} = $user->{lastLogon};
  $user->{lastLogon} = now_datetime;
  $user->save;

  my $cart = delete $session->{cart};
  undef $session;
  $req->clear_session;
  $session = $req->session;

  $session->{cart} = $cart;
  $session->{userid} = $user->id;

  $req->audit
    (
     object => $user,
     component => "siteuser:logon:success",
     actor => "S",
     level => "info",
     msg => "Site User '" . $user->userId . "' logged on",
    );

  if ($custom->can('siteuser_login')) {
    $custom->siteuser_login($session->{_session_id}, $session->{userid}, 
			    $cfg, $session);
  }

  $self->_send_user_cookie($user);

  return $self->_got_user_refresh($req);
}

sub _got_user_refresh {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $session = $req->session;

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
  my $refresh = $req->cgi->param('r');
  unless ($refresh) {
    if ($session->{userid}) {
      $refresh = $cfg->user_url("user", "userpage");
    }
    else {
      $refresh = $cfg->user_url("user", "show_logon");
    }
  }
  if ($need_magic) {
    my $base = $onbase ? $securl : $baseurl;
    my $finalbase = $onbase ? $baseurl : $securl;
    $refresh = $finalbase . $refresh unless $refresh =~ /^\w+:/;
    my $sessionid = $session->{_session_id};
    require BSE::SessionSign;
    my $sig = BSE::SessionSign->make($sessionid);
    my $url = $cfg->user_url("user", undef,
			     -base => $base,
			     setcookie => $sessionid,
			     s => $sig,
			     r => $refresh);
    print STDERR "Heading to $url to setcookie\n" if $debug;
    return $req->get_refresh($url);
  }
  else {
    return $req->get_refresh($refresh);
  }
}

=item setcookie

Used internally to propagate session cookie changes between the SSL
and non-SSL hosts.

=cut

sub req_setcookie {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $debug = $cfg->entryBool('debug', 'logon_cookies', 0);
  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $cookie = $cgi->param('setcookie')
    or return $self->req_show_logon($req, 
				$msgs->(nocookie=>"No cookie provided"));
  my $sig = $cgi->param("s")
    or return $self->req_show_logon($req,
				    $msgs->(nosig => "No signature for setcookie"));

  require BSE::SessionSign;
  my $error;
  unless (BSE::SessionSign->check($cookie, $sig, \$error)) {
    return $self->req_show_logon($req,
				    $msgs->(badsig => "Invalid signature for setcookie"));
  }
  print STDERR "Setting sessionid to $cookie for $ENV{HTTP_HOST}\n";
  my %newsession;
  BSE::Session->change_cookie($session, $cfg, $cookie, \%newsession);
  if (exists $session->{cart} && !exists $newsession{cart}) {
    $newsession{cart} = $session->{cart};
    $newsession{custom} = $session->{custom} if exists $session->{custom};
  }
  my $refresh = $cgi->param('r') 
    or return $self->req_show_logon($req, 
				$msgs->(norefresh=>"No refresh provided"));
  my $userid = $newsession{userid};
  my $user;
  if ($userid) {
    $user = BSE::TB::SiteUsers->getByPkey($userid);
  }
  $self->_send_user_cookie($user);

  refresh_to($refresh);

  return;
}

=item logoff

Log the user off.

This removes the user's session.

Redirects to the L</logon> page.

=cut

sub req_logoff {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  if ($nopassword) {
    return $self->req_nopassword($req);
  }

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $req->session->{userid}
    or return $self->req_show_logon($req, 
				$msgs->(notloggedon=>"You aren't logged on"));

  my $session_id = $req->session->{_session_id};
  $req->clear_session;

  my $custom = custom_class($cfg);
  if ($custom->can('siteuser_logout')) {
    $custom->siteuser_logout($session_id, $cfg);
  }

  return $self->_got_user_refresh($req);
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

=item show_register

Display the member registration page.

Tags: standard dynamic tags and:

=over

=item *

C<< old I<field> >> - display the value of I<field> as it was
previously submitted.

=item *

C<message> - any error messages from the form submission.

=item *

C<< iterator ... subscriptions >>, C<< subscription I<field> >> -
iterate over configured newsletter subscriptions.

=item *

C<< ifSubscribed >> - test if the user selected a subscription on
their previous form submission.

=item *

C<< ifRequired I<field> >> - test if the specified member field is required.

=item *

C<< error_img I<field> >> - display an error indicator for I<field>

=back

Template: F<user/register>

=cut

sub req_show_register {
  my ($self, $req, $message, $errors) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $user_register = $cfg->entryBool('site users', 'user_register', 1);
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  unless ($user_register) {
    if ($nopassword) {
      return $self->req_show_lost_password($req,
				       "Registration disabled");
    }
    else {
      return $self->req_show_logon($req,
			       "Registration disabled");
    }
  }
  $message = $req->message($message || $errors);

  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my $sub_index = -1;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     old => 
     sub {
       my $value = $cgi->param($_[0]);
       defined $value or $value = '';
       escape_html($value);
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

  $req->set_variable(subscriptions => \@subs);

  my $template = 'user/register';
  return $req->dyn_response($template, \%acts);
}

=item register

Register a new user.

=cut

sub req_register {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');

  my $user_register = $cfg->entryBool('site users', 'user_register', 1);
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  unless ($user_register) {
    my $msg = $msgs->(regdisabled => "Registration disabled");
    if ($nopassword) {
      return $self->req_show_lost_password($req, $msg);
    }
    else {
      return $self->req_show_logon($req, $msg);
    }
  }

  my %user;
  my @cols = BSE::TB::SiteUser->columns;
  shift @cols;

  my %errors;
  my %fields = BSE::TB::SiteUser->valid_fields($cfg);
  my %rules = BSE::TB::SiteUser->valid_rules($cfg);
  $req->validate(errors => \%errors,
		 fields => \%fields,
		 rules => \%rules,
		 section => 'site user validation');

  my $email = $cgi->param('email');
  $email =~ s/^\s+|\s+$//g;
  if (!defined $email or !length $email) {
    $errors{email} = $msgs->(regnoemail => "Please enter an email address");
    $email = ''; # prevent undefined value warnings later
  }
  elsif ($email !~ /.\@./) {
    $errors{email} = $msgs->(regbademail => "Please enter a valid email address");
  }
  if ($nopassword) {
    my $confemail = $cgi->param('confirmemail');
    $confemail =~ s/^\s+|\s+$//g;
    if (!defined $confemail or !length $confemail) {
      $errors{confirmemail} = $msgs->(regnoconfemail => "Please enter a confirmation email address");
    }
    elsif ($email ne $confemail) {
      $errors{confirmemail} = $msgs->(regbadconfemail => "Confirmation email must match the email address");
    }
    my $user = BSE::TB::SiteUsers->getBy(userId=>$email);
    if ($user) {
      $errors{email} = $msgs->(regemailexists=>
				"Sorry, email $email already exists as a user",
				$email);
    }
    $user{userId} = $email;
    $user{password} = '';
  }
  else {
    my $userid = $cgi->param('userid');
    my @errors;
    if (!defined $userid || length $userid == 0) {
      $errors{userid} = $msgs->(reguser=>"Please enter your username");
    }
    my %others = map { $_ => scalar($cgi->param($_)) }
      BSE::TB::SiteUser->password_check_fields;
    my $pass = $cgi->param('password');
    my $pass2 = $cgi->param('confirm_password');
    if (!defined $pass || length $pass == 0) {
      $errors{password} = $msgs->(regpass=>"Please enter your password");
    }
    elsif (!BSE::TB::SiteUser->check_password_rules
	   (
	    password => $pass,
	    username => $userid,
	    errors => \@errors,
	    other => \%others,
	   )) {
      $errors{password} = \@errors;
    }
    elsif (!defined $pass2 || length $pass2 == 0) {
      $errors{confirm_password} = 
	$msgs->(regconfpass=>"Please enter a confirmation password");
    }
    elsif ($pass ne $pass2) {
      $errors{confirm_password} = 
	$msgs->(regconfmismatch=>"The confirmation password is different from the password");
    }
    my $user = BSE::TB::SiteUsers->getBy(userId=>$userid);
    if ($user) {
      # give the user a suggestion
      my $workuser = $userid;
      $workuser =~ s/\d+$//;
      my $suffix = 1;
      for my $suffix (1..100) {
	unless (BSE::TB::SiteUsers->getBy(userId=>"$workuser$suffix")) {
	  $cgi->param(userid=>"$workuser$suffix");
	  last;
	}
      }
      $errors{userid} = $msgs->(regexists=>
				"Sorry, username $userid already exists",
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
  my $aff_name = $cgi->param('affiliate_name');
  $aff_name = _validate_affiliate_name($cfg, $aff_name, \%errors, $msgs);
  defined $aff_name or $aff_name = '';

  if (keys %errors) {
    return $self->req_show_register($req, undef, \%errors);
  }

  $user{email} = $email;
  $user{affiliate_name} = $aff_name;
  if ($nopassword) {
    use BSE::Util::Secure qw/make_secret/;
    $user{password} = make_secret($cfg);
  }

  my $user;
  eval {
    $user = BSE::TB::SiteUsers->make(%user);
  };
  if ($user) {
    my $custom = custom_class($cfg);
    $custom->can('siteuser_add')
      and $custom->siteuser_add($user, 'user', $cfg);

    $req->audit
      (
       actor => $user,
       object => $user,
       component => "member:register:created",
       msg => "Site User '" . $user->userId . "' created",
       level => "notice",
      );

    $self->_send_user_cookie($user);
    unless ($nopassword) {
      $session->{userid} = $user->id;
      my $custom = custom_class($cfg);
      if ($custom->can('siteuser_login')) {
	$custom->siteuser_login($session->{_session_id}, $session->{userid}, $cfg);
      }
    }

    if ($cfg->entry('site users', 'notify_register', 0)) {
      $self->_notify_registration($req, $user);
    }

    my $subs = $self->_save_subs($user, $session, $cfg, $cgi);
    if ($nopassword) {
      return $self->send_conf_request($req, $user);
    }
    elsif ($subs) {
      my $page = $self->send_conf_request($req, $user, 1);
      $page and return $page;
    }
    elsif ($cfg->entry('site users', 'notify_register_customer')) {
      $user->send_registration_notify
	(
	 remote_addr => $req->ip_address
	);
    }

    $custom->siteusers_changed($cfg);

    $req->flash_notice("msg:bse/user/register", [ $user ]);

    return $self->_got_user_refresh($req);
  }
  else {
    return $self->req_show_register($req, $msgs->(regdberr=> "Database error $@"));
  }
}

sub _get_user {
  my ($self, $req, $name, $result) = @_;

  defined $result or confess "Missing result parameter";

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  if ($nopassword) {
    my $password;
    $password = $cgi->param($name) if $name;
    $password ||= $cgi->param('p');
    my $uid = $cgi->param('u');
    defined $uid && $uid =~ /^\d+$/ && defined $password
      or do { refresh_to($ENV{SCRIPT}."?nopassword=1"); return };

    my $user = BSE::TB::SiteUsers->getByPkey($uid)
      or do { refresh_to($ENV{SCRIPT}."?nopassword=1"); return };

    $user->{password} eq $password
      or do { refresh_to($ENV{SCRIPT}."?nopassword=1"); return };

    return $user;
  }
  else {
    if ($cfg->entryBool('custom', 'user_auth')) {
      my $custom = custom_class($cfg);

      return $custom->siteuser_auth($session, $cgi, $cfg);
    }
    else {
      my $user = $req->siteuser;
      unless ($user) {
	$$result = $self->req_show_logon($req);
	return;
      }
      if ($user->{disabled}) {
	$$result = $self->req_show_logon($req, "Account disabled");
	return;
      }

      return $user;
    }
  }
}

sub tag_ifSubscribedTo {
  my ($user, $args) = @_;

  require BSE::TB::Subscriptions;
  my $sub = BSE::TB::Subscriptions->getBy(text_id=>$args)
    or return 0;

  $user->subscribed_to($sub);
}

sub _partial_logon {
  my ($self, $req) = @_;

  my $session = $req->session;
  if ($session->{partial_logon} 
      && !$req->cfg->entryBool('custom', 'user_auth')) {
    my $user = BSE::TB::SiteUsers->getByPkey($session->{partial_logon})
      or return;
    $user->{disabled}
      and return;
    return $user;
  }
  return;
}

=item show_opts

Display the user options page.

This page is also displayed if the user logs on and not all required
fields are populated.

Tags: L</Standard user page tags> and:

=over

=item *

C<< last I<field> >> - the previous form submitted value for I<field>
or that field from the user record.

=item *

C<message> - an error messages from the previous form submission.

=item *

C<< iterator ... subscriptions >>, C<< subscription I<field> >> -
iterate over configured newsletter subscriptions.

=item *

C<< ifSubscribed >> - test if the user selected a subscription on
their previous form submission, or if the user is subscribed to this
newsletter subscription.

=item *

C<ifUserSubs> - test if the user is subscribed to anything.

=item *

C<< error_img I<field> >> - display an error indicator for I<field>.

=item *

C<<partial_logon>> - test if the user is only partly logged on.

=item *

C<< iterator ... filecats >>, C<< filecat I<field> >> - iterate over
the configured file categories.

=back

Template: F<user/options>

=cut

sub req_show_opts {
  my ($self, $req, $message, $errors) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $partial_logon = 0;
  my $user = $self->_partial_logon($req)
    and ++$partial_logon;

  if ($partial_logon) {
    $cgi->param('t' => undef);
  }

  unless ($user) {
    my $result;
    $user = $self->_get_user($req, 'show_opts', \$result)
      or return $result;
  }
  
  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my @usersubs = BSE::SubscribedUsers->getBy(userId=>$user->{id});
  my %usersubs = map { $_->{subId}, $_ } @usersubs;
  
  my $sub_index;
  $message = $req->message($message || $errors);

  require BSE::TB::OwnedFiles;
  my @file_cats = BSE::TB::OwnedFiles->categories($cfg);
  my %subbed = map { $_ => 1 } $user->subscribed_file_categories;
  for my $cat (@file_cats) {
    $cat->{subscribed} = exists $subbed{$cat->{id}} ? 1 : 0;
  }

  $req->set_variable(file_cats => \@file_cats);
  $req->set_variable(subscriptions => \@subs);

  my $it = BSE::Util::Iterate->new;
  my %acts;
  %acts =
    (
     $self->_common_tags($req, $user),
     last => 
     sub {
       my $value = $cgi->param($_[0]);
       defined $value or $value = $user->{$_[0]};
       defined $value or $value = '';
       escape_html($value);
     },
     message => $message,
     BSE::Util::Tags->make_iterator(\@subs, 'subscription', 'subscriptions',
				    \$sub_index),
     ifSubscribed=>sub { $usersubs{$subs[$sub_index]{id}} },
     ifAnySubs => sub { @usersubs },
     ifRequired =>
     [ \&tag_if_required, $cfg ],
     error_img => [ \&tag_error_img, $cfg, $errors ],
     $self->_edit_tags($user, $cfg),
     ifSubscribedTo => [ \&tag_ifSubscribedTo, $user ],
     partial_logon => $partial_logon,
     $it->make
     (
      data => \@file_cats,
      single => "filecat",
      plural => "filecats"
     ),
    );

  my $base = 'user/options';

  return $req->dyn_response($base, \%acts);
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
	  my $other = BSE::TB::SiteUsers->getBy(userId=>$email);
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

=item saveopts

Save options prompted for by L</show_opts>

=cut

sub req_saveopts {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  
  my $partial_logon = 0;
  my $user = $self->_partial_logon($req)
    and ++$partial_logon;

  unless ($user) {
    my $result;
    $user = $self->_get_user($req, undef, \$result)
      or return $result;
  }

  my $custom = custom_class($cfg);
  if ($cfg->entry('custom', 'saveopts')) {
    local $SIG{__DIE__};
    eval {
      $custom->siteuser_saveopts($user, $req);
    };
    if ($@) {
      return $self->req_show_opts($req, $@);
    }
  }

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  my %errors;
  my $newpass;
  unless ($nopassword) {
    my $oldpass = $cgi->param('old_password');
    $newpass = $cgi->param('password');
    my $confirm = $cgi->param('confirm_password');
    
    if (defined $newpass && length $newpass) {
      if ($oldpass) {
	my $error;
	if (!$user->check_password($oldpass, \$error)) {
	  sleep 5; # yeah, it's ugly
	  $errors{old_password} = $msgs->(optsbadold=>"You need to enter your old password to change your password")
	}
	else {
	  my @errors;
	  my %others;
	  %others = map { $_ => $user->$_() } BSE::TB::SiteUser->password_check_fields;
	  if (!BSE::TB::SiteUser->check_password_rules
	      (
	       password => $newpass,
	       errors => \@errors,
	       username => $user->userId,
	       other => \%others
	      )) {
	    $errors{password} = \@errors;
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
  $email =~ s/^\s+|\s+$//g;
  my $saveemail;
  if (defined $email) {
    ++$saveemail;
    _checkemail($user, \%errors, $email, $cgi, $msgs, $nopassword);
  }

      
  my @cols = grep !$donttouch{$_}, BSE::TB::SiteUser->columns;
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
  my %fields = $user->valid_fields($cfg);
  unless ($partial_logon) {
    # only test fields for values supplied
    my @remove = grep !defined $cgi->param($_), keys %fields;
    delete @fields{@remove};
  }
  my %rules = $user->valid_rules($cfg);
  $req->validate(errors => \%errors,
		 fields => \%fields,
		 rules => \%rules,
		 section => 'site user validation');

  my $aff_name = $cgi->param('affiliate_name');
  $aff_name = _validate_affiliate_name($cfg, $aff_name, \%errors, $msgs, $user);

  $self->_save_images($cfg, $cgi, $user, \%errors);

  keys %errors
    and return $self->req_show_opts($req, undef, \%errors);
  my $newemail;
  if ($saveemail && $email ne $user->{email}) {
    $user->{confirmed} = 0;
    $user->{confirmSecret} = '';
    $user->{email} = $email;
    $user->{userId} = $email if $nopassword;
    ++$newemail;
  }
  if (!$nopassword && $newpass) {
    $user->changepw($newpass, $user);
  }

  $user->{affiliate_name} = $aff_name if defined $aff_name;
  
  for my $col (@cols) {
    my $value = $cgi->param($col);
    if (defined $value) {
      $user->{$col} = $value;
    }
  }

  $user->{textOnlyMail} = 0 
    if $cgi->param('saveTextOnlyMail') && !defined $cgi->param('textOnlyMail');
  $user->save;

  # subscriptions
  my $subs;
  if ($cgi->param('saveSubscriptions')) {
    $subs = $self->_save_subs($user, $session, $cfg, $cgi);
  }

  $custom->can('siteuser_edit')
    and $custom->siteuser_edit($user, 'user', $cfg);

  if ($nopassword) {
    return $self->send_conf_request($req, $user)
      if $newemail;
  }
  else {
    $subs = () = $user->subscriptions unless defined $subs;
    return $self->send_conf_request($req, $user)
      if $subs && !$user->{confirmed};
  }

  if ($cgi->param('save_file_subs')) {
    my @new_subs = $cgi->param("file_subscriptions");
    $user->set_subscribed_file_categories($cfg, @new_subs);
  }

  if ($partial_logon) {
    $user->{previousLogon} = $user->{lastLogon};
    $user->{lastLogon} = now_datetime;
    $session->{userid} = $user->id;
    delete $session->{partial_logon};
    $user->save;

    my $custom = custom_class($cfg);
    if ($custom->can('siteuser_login')) {
      $custom->siteuser_login($session->{_session_id}, $session->{userid}, $cfg);
    }

    $self->_send_user_cookie($user);

    return $self->_got_user_refresh($req);
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

  $req->flash_notice("msg:bse/user/saveopts", [ $user ]);

  $custom->siteusers_changed($cfg);

  return $req->get_refresh($url);
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

sub iter_usersubs {
  my ($user) = @_;

  $user->subscribed_services;
}

sub iter_sembookings {
  my ($user) = @_;

  $user->seminar_bookings_detail;
}

sub tag_order_item_options {
  my ($self, $req, $ritem) = @_;

  $$ritem
    or return "** only usable in the items iterator **";

  my $item = $$ritem;
  require BSE::Shop::Util;
  BSE::Shop::Util->import(qw/order_item_opts nice_options/);
  my @options;
  if ($item->{options}) {
    # old order
    require BSE::TB::Products;
    my $product = BSE::TB::Products->getByPkey($item->{productId});

    @options = order_item_opts($req, $item, $product);
  }
  else {
    @options = order_item_opts($req, $item);
  }

  return nice_options(@options);
}

sub iter_orders {
  my ($self, $user) = @_;

  require BSE::TB::Orders;
  return sort { $b->{orderDate} cmp $a->{orderDate}
		  || $b->{id} <=> $a->{id} }
    grep $_->complete, BSE::TB::Orders->getBy(userId=>$user->{userId});
}

sub iter_order_items {
  my ($self, $rorder) = @_;

  $$rorder or return "** Not in the order iterator **";

  return $$rorder->items;
}

sub iter_orderfiles {
  my ($self, $rorder) = @_;

  $$rorder or return;

  return $$rorder->files;
}

=item userpage

Display general information to the user.

Tags: L</Standard user page tags> and:

=over

=item *

C<message> - any error messages.

=item *

C<< iterator ... subscriptions >>, C<< subscription I<field> >> -
iterater over subscribed services (B<not> newsletter subscriptions)

=item *

C<< iterator ... bookings >>, C<< booking I<field> >> - iterate over
user seminar bookings.

=back

Template: F<user/userpage>.

=cut

sub req_userpage {
  my ($self, $req, $message) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  $message = $req->message($message);

  my $result;
  my $user = $self->_get_user($req, 'userpage', \$result)
    or return $result;

  my $it = BSE::Util::Iterate->new;
  my %acts =
    (
     $self->_common_tags($req, $user),
     message => $message,
     $it->make_iterator([ \&iter_usersubs, $user ], 
			'subscription', 'subscriptions'),
     $it->make_iterator([ \&iter_sembookings, $user ],
			'booking', 'bookings'),
    );
  my $base_template = 'user/userpage';

  return $req->dyn_response($base_template, \%acts);
}

sub tag_detail_product {
  my ($ritem, $products, $field) = @_;

  $$ritem or return '';
  my $product = $products->{$$ritem->{productId}}
    or return '';

  defined $product->{$field} or return '';

  return escape_html($product->{$field});
}

sub iter_detail_productfiles {
  my ($ritem, $files) = @_;

  $$ritem or return;

  grep $$ritem->{productId} == $_->{articleId}, @$files;
}

sub tag_detail_ifFileAvail {
  my ($order, $rfile, $must_be_paid, $must_be_filled) = @_;

  $$rfile or return 0;
  $$rfile->{forSale} or return 1;

  return 0 if $must_be_paid && !$order->{paidFor};
  return 0 if $must_be_filled && !$order->{filled};

  return 1;
}

=item orderdetail

Display an order detail for an order for the currently logged in user.

Parameters:

=over

=item *

id - order id (the logged in user must own this order)

=back

See _orderdetail_low for tags.

Template: F<user/orderdetail>

=cut

sub req_orderdetail {
  my ($self, $req, $message) = @_;

  my $cgi = $req->cgi;

  my $result;
  my $user = $self->_get_user($req, 'userpage', \$result)
    or return $result;
  my $order_id = $cgi->param('id');
  my $order;
  if (defined $order_id && $order_id =~ /^\d+$/) {
    require BSE::TB::Orders;
    $order = BSE::TB::Orders->getByPkey($order_id);
  }
  $order->{userId} eq $user->{userId} || $order->{siteuser_id} == $user->{id}
    or undef $order;
  $order
    or return $self->req_userpage($req, "No such order");

  return $self->_orderdetail_low($req, $order, $message, "user/orderdetail", 0);
}

=item orderdetaila

=item oda

Display an order detail for an order identified by the order's
randomId.

Parameters:

=over

=item *

id - order randomId

=back

See _orderdetail_low for tags.

Template: F<user/orderdetaila>

=cut

sub req_orderdetaila {
  my ($self, $req, $message) = @_;

  my $cgi = $req->cgi;

  my $result;
  my $order_id = $cgi->param('id');
  my $order;
  if (defined $order_id && $order_id =~ /^[a-f0-9]{32,}$/) {
    require BSE::TB::Orders;
    ($order) = BSE::TB::Orders->getBy(randomId => $order_id);
  }
  $order
    or return $self->req_show_logon($req, "No such order");

  return $self->_orderdetail_low($req, $order, $message, "user/orderdetaila", 1);
}

*req_oda = \&req_orderdetaila;

=item _orderdetail_low

Common tags for orderdetail and orderdetaila.

=over

=item *

order I<field> - field from the order.

=item *

iterator items

=item *

item I<field> - access to the items in the order

=item *

iterator orderfiles

orderfile I<field> - access to files bought in the order.  Note: the
user will need to logon to download forSale files, even from the
anonymous order detail page.

=back

Variables:

=over

=item *

C<order> - the order object to display the details of.

=back

=cut

sub _orderdetail_low {
  my ($self, $req, $order, $message, $template, $anon) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;

  $message ||= $cgi->param('message') || '';

  my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  my $must_be_filled = $cfg->entryBool('downloads', 'must_be_filled', 0);

  my @items = $order->items;
  my @files = $order->files;
  my @products = $order->products;
  my %products = map { $_->{id} => $_ } @products;
  my $current_item;
  my $current_file;

  my $it = BSE::Util::Iterate->new;

  my %acts;
  %acts =
    (
     $anon ? $req->dyn_user_tags() : $self->_common_tags($req, $req->siteuser),
     $order->tags(),
     message => sub { escape_html($message) },
     ifAnon => !!$anon,
    );

  $req->set_variable(order => $order);

  return $req->dyn_response($template, \%acts);
}

sub _common_download {
  my ($self, $req, $file) = @_;

  my $cfg = $req->cfg;
  my $user = $req->siteuser;
  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');

  $cfg->entryBool('downloads', 'require_logon', 0) && !$user
    and return $self->req_show_logon($req,
			  $msgs->('downloadlogonall', 
				  "You must be logged on to download files"));
    
  $file->{requireUser} && !$user
    and return $self->req_show_logon($req,
			  $msgs->('downloadlogon',
				  "You must be logged on to download this file"));
  if ($file->forSale) {
    my $error;
    unless ($file->downloadable_by($user, \$error)) {
      return $self->req_show_logon($req, { _ => "msg:bse/user/downloaderror/$error"});
    }
  }

  # check the user has access to this file (RT#531)
  my $article;
  if ($file->{articleId} != -1) {
    require BSE::TB::Articles;
    $article ||= BSE::TB::Articles->getByPkey($file->{articleId})
      or return $self->req_show_logon($req,
				  $msgs->('downloadarticle',
					  "Could not load article for file"));
    if ($article->is_dynamic && !$req->siteuser_has_access($article)) {
      if ($req->siteuser) {
	return $self->req_userpage($req, $msgs->('downloadnoaccess',
					     "You do not have access to this article"));
      }
      else {
	my $cfg = $req->cfg;
	my $refresh = "/cgi-bin/user.pl?file=" . $file->id;
	my $logon =
	  $cfg->entry('site', 'url') . "/cgi-bin/user.pl?show_logon=1&r=".escape_uri($refresh)."&m=You+need+to+logon+download+this+file";
	return $req->get_refresh($logon);
	return;
      }
    }
  }

  # this this file is on an external storage, and qualifies for
  # external storage send the user to get it from there
  if ($file->{src} && $file->{storage} ne 'local'
      && !$file->{forSale} && !$file->{requireUser}
      && (!$article || !$article->is_access_controlled)) {
    return $req->get_refresh($file->{src});
  }
  
  my $filebase = $cfg->entryVar('paths', 'downloads');
  my $filename = "$filebase/$file->{filename}";
  -r $filename
    or return $self->req_show_logon($req, 
	       $msgs->(openfile =>
		       "Sorry, cannot open that file.  Contact the webmaster.",
		       $!));

  my %result =
    (
     # downloads over https of non-HTML to IE causes a confusing error
     # if cache-control is "no-cache".  Avoid setting that.
     no_cache_dynamic => 0,
    );
  my @headers;
  $result{content_filename} = $filename;
  push @headers, "Content-Length: $file->{sizeInBytes}";
  if ($file->{download}) {
    $result{type} = "application/octet-stream";
    push @headers,
      qq/Content-Disposition: attachment; filename=$file->{displayName}/;
  }
  else {
    $result{type} = $file->{contentType};
    push @headers,
      qq/Content-Disposition: inline; filename=$file->{displayName}/;
  }
  $result{headers} = \@headers;

  return \%result;
}

=item download

Download a purchased file.

See also L</download_file> which requires only a file id.

Parameters:

=over

=item *

C<order> - order id where access to the file was purchased

=item *

C<file> - file id of the purchased file.

=back

=cut

sub req_download {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $result;
  my $user = $self->_get_user($req, 'show_opts', \$result)
    or return $result;

  my $orderid = $cgi->param('order')
    or return _refresh_userpage($cfg, $msgs->('noorderid', "No order id supplied"));
  require BSE::TB::Orders;
  my $order = BSE::TB::Orders->getByPkey($orderid)
    or return _refresh_userpage($cfg, $msgs->('nosuchorder',
					"No such order $orderid", $orderid));
  unless (length $order->{userId}
	  && $order->{userId} eq $user->{userId}) {
    return _refresh_userpage($cfg, $msgs->("notyourorder",
				     "Order $orderid isn't yours", $orderid));
  }

  require BSE::TB::ArticleFiles;
  my $fileid = $cgi->param('file')
    or return _refresh_userpage($cfg, $msgs->(nofileid=>"No file id supplied"));
  my $file = BSE::TB::ArticleFiles->getByPkey($fileid);
  my @items = $order->items;
  unless ($file && grep($_->productId == $file->articleId, @items)) {
    return _refresh_userpage($cfg, $msgs->(nosuchfile=>"No such file in that line item"));
  }

  return $self->_common_download($req, $file);

  # my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  # my $must_be_filled = $cfg->entryBool('downloads', 'must_be_filled', 0);
  # if ($must_be_paid && !$order->{paidFor} && $file->{forSale}) {
  #   return _refresh_userpage($cfg, $msgs->("paidfor", 
  # 				     "Order not marked as paid for"));
  # }
  # if ($must_be_filled && !$order->{filled} && $file->{forSale}) {
  #   return _refresh_userpage($cfg, $msgs->("filled", 
  # 				     "Order not marked as filled"));
  # }
  
  # my $filebase = $cfg->entryVar('paths', 'downloads');
  # my $filename = "$filebase/$file->{filename}";
  # -r $filename
  #   or return _refresh_userpage($cfg, 
  # 	       $msgs->(openfile =>
  # 		       "Sorry, cannot open that file.  Contact the webmaster.",
  # 		       $!));
  # my %result =
  #   (
  #    # downloads over https of non-HTML to IE causes a confusing error
  #    # if cache-control is "no-cache".  Avoid setting that.
  #    no_cache_dynamic => 0,
  #   );
  # my @headers;
  # $result{content_filename} = $filename;
  # push @headers, "Content-Length: $file->{sizeInBytes}";
  # if ($file->{download}) {
  #   $result{type} = "application/octet-stream";
  #   push @headers,
  #     qq/Content-Disposition: attachment; filename=$file->{displayName}/;
  # }
  # else {
  #   $result{type} = $file->{contentType};
  #   push @headers,
  #     qq/Content-Disposition: inline; filename=$file->{displayName}/;
  # }
  # $result{headers} = \@headers;

  # return \%result;
}

=item download_file

Download a file.

Parameters:

=over

=item *

C<file> - the id of the file to download.  The user must have access
to download the file.

=back

=cut

sub req_download_file {
  my ($self, $req) = @_;

  my ($fileid) = split '/', $self->rest;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $session->{userid};
  my $user;
  if ($userid) {
    $user = BSE::TB::SiteUsers->getByPkey($userid);
  }
  $fileid ||= $cgi->param('file')
    or return $self->req_show_logon($req, 
			 $msgs->('nofileid', "No file id supplied"));
  require BSE::TB::ArticleFiles;
  my $file = BSE::TB::ArticleFiles->getByPkey($fileid)
    or return $self->req_show_logon($req,
				      $msgs->('nosuchfile', "No such download"));

  return $self->_common_download($req, $file);
}

=item file_metadata

Retrieve metadata for a file.

Parameters:

=over

=item *

C<file> - the id of the file to retrieve metadata for.

=item *

C<name> - the name of the metadata.

=back

=cut

sub req_file_metadata {
  my ($self, $req) = @_;

  my ($fileid, $metaname) = split '/', $self->rest;

  my $user = $req->siteuser;
  my $cgi = $req->cgi;
  $fileid ||= $cgi->param('file')
    or return $self->req_show_logon($req, $req->text(nofileid => "No file id supplied"));
  $metaname ||= $cgi->param('name')
    or return $self->req_show_logon($req, $req->text(nometaname => "No metaname supplied"));
  require BSE::TB::ArticleFiles;
  my $file = BSE::TB::ArticleFiles->getByPkey($fileid)
    or return $self->req_show_logon($req, $req->text(nosuchfile => "No such file"));
  
  if ($file->articleId != -1) {
    # check the user has access
    my $article = $file->article
      or return $self->req_show_logon($req, $req->text(nofilearticle => "No article found for this file"));
    if ($article->is_dynamic && !$req->siteuser_has_access($article)) {
      if ($req->siteuser) {
	return $self->req_userpage($req, $req->text(downloadnoacces => "You do not have access to this article"));
      }
      else {
	return $self->req_show_logon($req, $req->text(needlogon => "You need to logon to download this file"));
      }
    }
  }
  my $meta = $file->meta_by_name($metaname)
    or return $self->req_show_logon($req, $req->text(nosuchmeta => "There is no metadata by that name for this file"));

  my %result =
    (
     # downloads over https of non-HTML to IE causes a confusing error
     # if cache-control is "no-cache".  Avoid setting that.
     no_cache_dynamic => 0,

     type => $meta->content_type,
     content => $meta->value,
    );

  return \%result;
}

=item file_cmetadata

Retrieve generated metadata for a file.

=over

=item *

C<file> - the id of the file to retrieve metadata for.

=item *

C<name> - the name of the metadata.

=back

=cut

sub req_file_cmetadata {
  my ($self, $req) = @_;

  my ($fileid, $metaname) = split '/', $self->rest;

  my $user = $req->siteuser;
  my $cgi = $req->cgi;
  $fileid ||= $cgi->param('file')
    or return $self->req_show_logon($req, $req->text(nofileid => "No file id supplied"));
  $metaname ||= $cgi->param('name')
    or return $self->req_show_logon($req, $req->text(nometaname => "No metaname supplied"));
  require BSE::TB::ArticleFiles;
  my $file = BSE::TB::ArticleFiles->getByPkey($fileid)
    or return $self->req_show_logon($req, $req->text(nosuchfile => "No such file"));
  
  if ($file->articleId != -1) {
    # check the user has access
    my $article = $file->article
      or return $self->req_show_logon($req, $req->text(nofilearticle => "No article found for this file"));
    if ($article->is_dynamic && !$req->siteuser_has_access($article)) {
      if ($req->siteuser) {
	return $self->req_userpage($req, $req->text(downloadnoacces => "You do not have access to this article"));
      }
      else {
	return $self->req_show_logon($req, $req->text(needlogon => "You need to logon to download this file"));
      }
    }
  }
  my $meta = $file->metacontent(cfg => $req->cfg, name => $metaname)
    or return $self->req_show_logon($req, $req->text(nosuchmeta => "There is no metadata by that name for this file"));

  return $meta;
}

=item show_lost_password

Display the lost password form.

Tags: standard dynamic tags and:

=over

=item *

C<message>

=item *

C<< error_img I<field> >>

=back

Template: F<user/lostpassword>

=cut

sub req_show_lost_password {
  my ($self, $req, $message) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  $message ||= $cgi->param('message') || '';
  my $errors;
  if (ref $message) {
    $errors = $message;
    $message = $req->message($errors);
  }
  elsif ($message) {
    $message = escape_html($message);
    $errors = {};
  }

  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     message => $message,
     error_img => [ \&tag_error_img, $cfg, $errors ],
    );

  return $req->dyn_response('user/lostpassword', \%acts);
}

=item lost_password

Process a lost password request.

Parameters:

=over

=item *

C<userid> - the user's logon name.

=back

On success, display:

Tags: standard dynamic tags and:

=over

=item *

C<message>

=item *

C<< user I<field> >> - user information.  Very little information from
this should be displayed.

=item *

C<< emailuser I<field> >> - usually the same as C<user>

=back

Template: F<user/lostemailsent>

=cut

sub req_lost_password {
  my ($self, $req, $message) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $cgi->param('userid');
  my %errors;
  
  unless (defined $userid && length $userid) {
    $errors{userid} = $msgs->(lostnouserid=> "Please enter your username");
  }
  
  my $user;
  unless (keys %errors) {
    $user = BSE::TB::SiteUsers->getBy(userId=>$userid)
      or $errors{userid} = $msgs->(lostnosuch=> "Unknown username supplied", $userid);
  }
  keys %errors
    and return $self->req_show_lost_password($req, \%errors);

  my $error;
  my $email_user = $user->lost_password(\$error)
    or return $self->req_show_lost_password
      ($req, $msgs->(lostmailerror=> "Email error: .$error", $error));
  $message = $message ? escape_html($message) : $req->message;
  my %acts;
  %acts = 
    (
     message => $message,
     $req->dyn_user_tags(),
     user => sub { escape_html($user->{$_[0]}) },
     emailuser => [ \&tag_hash, $email_user ],
    );

  return $req->dyn_response('user/lostemailsent', \%acts);
}

=item subinfo

Display information about a newletter subscription.

Tags: standard dynamic tags and:

=over

=item *

C<< subscription I<field> >> - the subscription being displayed.

=back

Template: F<user/subdetail>

=cut

sub req_subinfo {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $id = $cgi->param('id')
    or return $self->show_opts($req, "No subscription id parameter");
  my $sub = BSE::SubscriptionTypes->getByPkey($id)
    or return $self->show_opts($req, "Unknown subscription id");
  $req->set_variable(subscription => $sub);
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     subscription=>sub { escape_html($sub->{$_[0]}) },
    );

  return $req->dyn_response('user/subdetail', \%acts);
}

sub req_nopassword {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
    );

  return $req->dyn_response('user/nopassword', \%acts);
}

sub req_blacklist {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $email = $cgi->param('blacklist')
    or return $self->req_show_logon($req,
				$msgs->(blnoemail=>"No email supplied"));
  my $genemail = _generic_email($email);

  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     email => escape_html($email),
    );
  require BSE::EmailBlacklist;
  $req->set_variable(email => $email);
  my $black = BSE::EmailBlacklist->getEntry($genemail);
  if ($black) {
    return $req->dyn_response('user/alreadyblacklisted', \%acts);
  }
  my %black;
  my @cols = BSE::EmailBlackEntry->columns;
  shift @cols;
  $black{email} = $genemail;
  $black{why} = "Web request from $ENV{REMOTE_ADDR}";
  $black = BSE::EmailBlacklist->add(@black{@cols});

  return $req->dyn_response('user/blacklistdone', \%acts);
}

sub req_confirm {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $secret = $cgi->param('confirm')
    or return $self->req_show_logon($req,
				$msgs->(confnosecret=>"No secret supplied for confirmation"));
  my $userid = $cgi->param('u')
    or return $self->req_show_logon($req,
				$msgs->(confnouser=>"No user id supplied for confirmation"));
  if ($userid + 0 != $userid || $userid < 1) {
    return $self->req_show_logon($req,
			     $msgs->(confbaduser=>"Invalid or unknown user id supplied for confirmation"));
  }
  my $user = BSE::TB::SiteUsers->getByPkey($userid)
    or return $self->req_show_logon($req,
			     $msgs->(confbaduser=>"Invalid or unknown user id supplied for confirmation"));
  unless ($secret eq $user->{confirmSecret}) {
    return $self->req_show_logon($req, 
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
     $req->dyn_user_tags(),
     user=>sub { escape_html($user->{$_[0]}) },
    );

  return $req->dyn_response('user/confirmed', \%acts);
}

sub _generic_email {
#  BSE::TB::SiteUser->generic_email(shift);
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

# returns non-zero if a page was generated
sub send_conf_request {
  my ($self, $req, $user, $suppress_success) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);

  # check for existing in-progress confirmations
  my $checkemail = _generic_email($user->{email});

  # check the blacklist
  require BSE::EmailBlacklist;

  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     user=>sub { escape_html($user->{$_[0]}) },
    );
  
  # check that the from address has been configured
  my $from = $cfg->entry('confirmations', 'from') || 
    $cfg->entry('shop', 'from')|| $SHOP_FROM;
  unless ($from) {
    $acts{mailerror} = sub { escape_html("Configuration Error: The confirmations from address has not been configured") };
    return $req->dyn_response('user/email_conferror', \%acts);
  }

  my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);

  if ($blackentry) {
    $acts{black} = sub { escape_html($blackentry->{$_[0]}) },
    return $req->dyn_response('user/blacklisted', \%acts);
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
    $acts{confirm} = sub { escape_html($confirm->{$_[0]}) };
    my $too_many = $confirm->{unackedConfMsgs} >= MAX_UNACKED_CONF_MSGS;
    $acts{ifTooMany} = sub { $too_many };
    use BSE::Util::SQL qw/sql_datetime_to_epoch/;
    my $lastSentEpoch = sql_datetime_to_epoch($confirm->{lastConfSent});
    my $too_soon = $lastSentEpoch + MIN_UNACKED_CONF_GAP > time;
    $acts{ifTooSoon} = sub { $too_soon };
    # check how many
    if ($too_many) {
      return $req->dyn_response('user/toomany', \%acts);
    }
    if ($too_soon) {
      return $req->dyn_response('user/toosoon', \%acts);
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

  require BSE::ComposeMail;
  my $mail = BSE::ComposeMail->new(cfg => $cfg);

  my $subject = $cfg->entry('confirmations', 'subject') 
    || 'Subscription Confirmation';
  unless ($mail->send(template => $email_template,
	acts => \%confacts,
	from=>$from,
	to=>$user->{email},
	subject=>$subject)) {
    # a problem sending the mail
    $acts{mailerror} = sub { escape_html($mail->errstr) };
    return $req->dyn_response('user/email_conferror', \%acts);
    return;
  }
  ++$confirm->{unackedConfMsgs};
  $confirm->{lastConfSent} = now_datetime;
  $confirm->save;
  return if $suppress_success;
  return $req->dyn_response($nopassword ? 'user/confsent_nop' : 'user/confsent', \%acts);
}

sub req_unsub {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $secret = $cgi->param('unsub')
    or return $self->req_show_logon($req,
				$msgs->(unsubnosecret=>"No secret supplied for unsubscribe"));
  my $userid = $cgi->param('u')
    or return $self->req_show_logon($req,
				$msgs->(unsubnouser=>"No user supplied for unsubscribe"));
  if ($userid + 0 != $userid || $userid < 1) {
    return $self->req_show_logon($req,
			     $msgs->(unsubbaduser=>"Invalid or unknown username supplied for unsubscribe"));
  }
  my $user = BSE::TB::SiteUsers->getByPkey($userid)
    or return $self->req_show_logon($req,
			     $msgs->(unsubbaduser=>"Invalid or unknown username supplied for unsubscribe"));
  unless ($secret eq $user->{confirmSecret}) {
    return $self->req_show_logon($req, 
			     $msgs->(unsubbadsecret=>"Sorry, the ubsubscribe secret does not match"));

  }
  
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     user => sub { escape_html($user->{$_[0]}) },
    );
  my $subid = $cgi->param('s');
  my $sub;
  if ($subid eq 'all') {
    $user->removeSubscriptions();
    return $req->dyn_response('user/unsuball', \%acts);
  }
  elsif (0+$subid eq $subid 
	 and $sub = BSE::SubscriptionTypes->getByPkey($subid)) {
    $acts{subscription} = sub { escape_html($sub->{$_[0]}) };
    $user->removeSubscription($subid);
    return $req->dyn_response('user/unsubone', \%acts);
  }
  else {
    return $req->dyn_response('user/cantunsub', \%acts);
  }
}

sub _validate_affiliate_name {
  my ($cfg, $aff_name, $errors, $msgs, $user) = @_;

  my $display = $cfg->entry('site users', 'display_affiliate_name',
			    "Affiliate name");
  my $required = $cfg->entry('site users', 'require_affiliate_name', 0);

  if (defined $aff_name) {
    $aff_name =~ s/^\s+|\s+$//g;
    if (length $aff_name) {
      if ($aff_name =~ /^\w+$/) {
	my $other = BSE::TB::SiteUsers->getBy(affiliate_name => $aff_name);
	if ($other && (!$user || $other->{id} != $user->{id})) {
	  $errors->{affiliate_name} = $msgs->(dupaffiliatename =>
					    "$display '$aff_name' is already in use", $aff_name);
	}
	else {
	  return $aff_name;
	}
      }
      else {
	$errors->{affiliate_name} = $msgs->(badaffiliatename =>
					  "Invalid $display, no spaces or special characters are allowed");
      }
    }
    elsif ($required) {
      $errors->{affiliate_name} = $msgs->("optsrequired" =>
					  "$display is a required field",
					  "affiliate_name", $display);
    }
    else {
      return '';
    }
  }

  # always required if making a new user
  if (!$errors->{affiliate_name} && $required && !$user) {
    $errors->{affiliate_name} = $msgs->("optsrequired" =>
					"$display is a required field",
					"affiliate_name", $display);
  }

  return;
}

sub req_image {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  my $cgi = $req->cgi;
  my $session = $req->session;

  my $u = $cgi->param('u');
  my $i = $cgi->param('i');
  defined $u && $u =~ /^\d+$/ && defined $i && $i =~ /^\w+$/
    or return $self->req_show_logon($req, "Missing or bad image parameter");

  my $user = BSE::TB::SiteUsers->getByPkey($u)
    or return $self->req_show_logon($req, "Missing or bad image parameter");
  my $image = $user->get_image($i)
    or return $self->req_show_logon($req, "Unknown image id");
  my $image_dir = $cfg->entryVar('paths', 'siteuser_images');

  my $filename = "$image_dir/$image->{filename}";
  -r $filename
    or return $self->req_show_logon($req, "Image file missing");
  my %result =
    (
     type => $image->{content_type},
     content_filename => $filename,
     headers =>
     [
      "Content-Length: $image->{bytes}",
     ],
    );

  return \%result;
}

sub _notify_registration {
  my ($self, $req, $user) = @_;

  my $cfg = $req->cfg;

  my $email = $cfg->entry('site users', 'notify_register_email', 
			  $Constants::SHOP_FROM);
  $email ||= $cfg->entry('shop', 'from');
  unless ($email) {
    print STDERR "No email configured for notify_register, set [site users].notify_register_email\n";
    return;
  }
  print STDERR "email $email\n";

  my $subject = $cfg->entry('site users', 'notify_register_subject',
			    "New user {userId} registered");

  $subject =~ s/\{(\w+)\}/defined $user->{$1} ? $user->{$1} : "** $1 unknown **"/ge;
  $subject =~ tr/ -~//cd;
  substr($subject, 80) = '...' if length $subject > 80;
  
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     user => [ \&tag_hash_plain, $user ],
    );

  require BSE::ComposeMail;
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);
  $mailer->send(template => 'admin/registeremail',
		acts => \%acts,
		to => $email,
		from => $email,
		subject => $subject,
                log_object => $user,
                log_msg => "Notify admin that a Site User registered ($email)",
                log_component => "member:register:notifyadmin");
}

#sub error {
#  my ($self, $req, $error) = @_;
#
#  my $result = $self->SUPER::error($req, $error);
#
#  BSE::Template->output_result($req, $result);
#}

=item req_wishlist

Display a given user's wishlist.

Parameters:

=over

=item *

user - user logon of the user to display the wishlist for

=back

Template: user/wishlist.tmpl

Tags:

=over

=item *

C<< iterator begin uwishlist ... iterator end uwishlist >> - iterate
over the wishlist.

=item *

C<< uwishlistentry I<field> >> - retrieve a value from the entry.

=back

=cut

sub req_wishlist {
  my ($self, $req) = @_;

  my $user_id = $req->cgi->param('user');

  defined $user_id && length $user_id
    or return $self->error($req, "Invalid or missing user id");

  my $custom = custom_class($req->cfg);

  my $user = BSE::TB::SiteUsers->getBy(userId => $user_id)
    or return $self->error($req, "No such user $user_id");

  my $curr_user = $req->siteuser;

  $custom->can_user_see_wishlist($user, $curr_user, $req)
    or return $self->error($req, "Sorry, you cannot see ${user_id}'s wishlist");

  $req->set_variable(wuser => $user);

  my %acts;
  my $it = BSE::Util::Iterate::Article->new(req => $req);
  %acts =
    (
     $req->dyn_user_tags(),
     $it->make_iterator(sub { $user->wishlist },
			'uwishlistentry', 'uwishlist'),
     wuser => [ \&tag_hash, $user ],
    );

  my $template = 'user/wishlist';
  my $t = $req->cgi->param('_t');
  if ($t && $t =~ /^\w+$/ && $t ne 'base') {
    $template .= "_$t";
  }

  return $req->dyn_response($template, \%acts);
}

=item req_downufile

Download a user file.

=cut

sub req_downufile {
  my ($self, $req) = @_;

  require BSE::TB::OwnedFiles;
  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $id = $cgi->param("id");
  defined $id && $id =~ /^\d+$/
    or return $self->error($req, "Invalid or missing file id");

  # return the same error to avoid giving someone a mechanism to find
  # which files are in use
  my $file = BSE::TB::OwnedFiles->getByPkey($id)
    or return $self->error($req, "Invalid or missing file id");

  my $result;
  my $user = $self->_get_user($req, 'downufile', \$result)
    or return $result;

  require BSE::TB::SiteUserGroups;
  my $accessible = 0;
  if ($file->owner_type eq $user->file_owner_type) {
    $accessible = $user->id == $file->owner_id;
  }
  elsif ($file->owner_type eq BSE::TB::SiteUserGroup->file_owner_type) {
    my $owner_id = $file->owner_id;
    my $group = $owner_id < 0
      ? BSE::TB::SiteUserGroups->getQueryGroup($cfg, $owner_id)
      : BSE::TB::SiteUserGroups->getByPkey($owner_id);
    if ($group) {
      $accessible = $group->contains_user($user);
    }
    else {
      print STDERR "** downufile: unknown group id ", $file->owner_id, " in file ", $file->id, "\n";
    }
  }
  else {
    print STDERR "** downufile: Unknown file owner type ", $file->owner_type, " in file ", $file->id, "\n";
    $accessible = 0;
  }

  $accessible
    or return $self->error($req, "Sorry, you don't have access to this file");

  my $msg;
  $result = $file->download_result
    (
     cfg => $req->cfg,
     download => scalar($cgi->param("force_download")),
     msg => \$msg,
     user => $user,
    )
    or return $self->error($req, $msg);

  return $result;
}

=item lost

Prompt the user to enter a new password as part of account password
recovery.

Tags: standard dynamic tags and:

=over

=item *

C<lostid> - the password recovery id.  This should be supplied as an
C<id> parameter to C<lost_save>.

=item *

C<< error_img I<field> >> - error indicator for I<field>

=item *

C<< message >> - form submission error messages.

=back

=cut

sub req_lost {
  my ($self, $req, $errors) = @_;

  my ($id) = $self->rest;
  $id ||= $req->cgi->param("id");
  $id
    or return $self->req_show_logon($req, $req->catmsg("msg:bse/user/nolostid"));

  my $error;
  my $user = BSE::TB::SiteUsers->lost_password_next($id, \$error)
    or return $self->req_show_logon($req, { _ => "msg:bse/user/lost/$error" });

  my $message = $req->message($errors);

  my %acts =
    (
     $req->dyn_user_tags,
     lostid => $id,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     message => $message,
    );

  return $req->response("user/lost_prompt", \%acts);
}

=item lost_save

Save a new password for a user identified by a lost password recovery
id.

On success, refresh to the logon page with a success message.

On failure, show the logon page with an error message.

=cut

my %lost_fields =
  (
   password =>
   {
    description => "New Password",
    required => 1,
   },
   confirm =>
   {
    description => "Confirm Password",
    rules => "confirm",
    required => 1,
   },
  );

sub req_lost_save {
  my ($self, $req) = @_;

  my ($id) = $self->rest;
  $id ||= $req->cgi->param("id");
  $id
    or return $self->req_show_logon($req, $req->catmsg("msg:bse/user/nolostid"));

  my %errors;
  $req->validate(fields => \%lost_fields,
		 errors => \%errors);
  my $password = $req->cgi->param("password");
  my $tmp_user = BSE::TB::SiteUsers->lost_password_next($id);
  unless ($errors{password}) {
    my @errors;
    my %others = $tmp_user
      ? map { $_ => $tmp_user->$_() } BSE::TB::SiteUser->password_check_fields
	: ();
    $DB::single = 1;
    unless (BSE::TB::SiteUser->check_password_rules
	    (
	     password => $password,
	     errors => \@errors,
	     username => $tmp_user ? $tmp_user->userId : undef,
	     other => \%others,
	    )) {
      $errors{password} = \@errors;
    }
  }

  keys %errors
    and return $self->req_lost($req, \%errors);

  my $error;

  my $user = BSE::TB::SiteUsers->lost_password_save($id, $password, \$error)
    or return $self->req_show_logon($req, "msg:bse/user/lost/$error");

  $req->flash("msg:bse/user/lostsaved");

  return $req->get_refresh($req->cfg->user_url("user", "show_logon"));
}

=back

=head1 Standard user page tags

These are the standard dynamic tags, and:

=over

=item *

C<< user I<field> >> - access to the user.

=item *

C<< iterator ... orders >>, C<< order I<field> >> - iterate over user
orders.

=item *

C<< iterator ... items >>, C<< item I<field> >> - iterate over items
in the current order.

=item *

C<< iterator ... orderfiles >>, C<< orderfile I<field> >> - iterate
over the files for the current order.

=item *

C<< product I<field> >> - access to the product for the current order
item.

=item *

C<< iterator ... prodfiles >>, C<< prodfile I<field> >> - iterate over
the files for the product for the current order item.

=item *

C<< ifFileAvail >> - test if the current C<orderfile> or C<prodfile>
is available.

=item *

C<options> - product options selected for the current order line item.

=back

=cut

sub _common_tags {
  my ($self, $req, $user) = @_;

  my $cfg = $req->cfg;

  #my $order_index;
  #my $item_index;
  #my @items;
  my $item;
  my $product;
  #my @files;
  #my $file_index;
  my $file;
  my @orders;
  my $order;

  my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  my $must_be_filled = $cfg->entryBool('downloads', 'must_be_filled', 0);

  my $it = BSE::Util::Iterate->new(req => $req);
  my $ito = BSE::Util::Iterate::Objects->new();
  return
    (
     $req->dyn_user_tags(),
     user => [ \&tag_hash, $user ],
     $ito->make
     (
      data => \@orders,
      single => 'order',
      plural => 'orders',
      #index => \$order_index,
      code => [ iter_orders => $self, $user ],
      store => \$order,
     ),
     $it->make
     (
      single => "item",
      plural => "items",
      code => [ iter_order_items => $self, \$order ],
      store => \$item,
      changed => sub {
	my ($item) = @_;
	if ($item) {
	  $product = $item->product
	    or print STDERR "No product found for item $item->{id}\n";
	}
	else {
	  undef $product;
	}
	$req->set_article(product => $product);
      },
      nocache => 1,
     ),
     $it->make
     (
      single => "orderfile",
      plural => "orderfiles",
      code => [ iter_orderfiles => $self, \$order ],
      store => \$file,
      nocache => 1,
     ),
     product => sub {
       $item or return "* Not in item iterator *";
       $product or return "* No current product *";
       return tag_article($product, $cfg, $_[0]);
     },
     $it->make
     (
      single => "prodfile",
      plural => "prodfiles",
      code => [ files => $product ],
      store => \$file,
      nocache => 1,
     ),
     ifFileAvail =>
     sub {
       if ($file) {
	 return 1 if !$file->{forSale};
       }
       return 0 if $must_be_paid && !$order->paidFor;
       return 0 if $must_be_filled && !$order->filled;
       return 1;
     },
     options => [ tag_order_item_options => $self, $req, \$item ],
    );
}

1;

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
