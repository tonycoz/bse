package BSE::UserReg;
use strict;
use SiteUsers;
use BSE::Util::Tags;
use BSE::Template;
use Constants qw($SHOP_FROM);
use BSE::Message;
use BSE::SubscriptionTypes;
use BSE::SubscribedUsers;
use BSE::Mail;
use BSE::EmailRequests;

use constant MAX_UNACKED_CONF_MSGS => 3;
use constant MIN_UNACKED_CONF_GAP => 2 * 24 * 60 * 60;

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
  $session->{userid} = $user->{userId};
  use CGI::Cookie;
  print "Set-Cookie: ",CGI::Cookie->new(-name=>"userid", 
					-value=>$user->{userId},
					-path=>"/"),"\n";

  _got_user_refresh($session, $cgi, $cfg);
}

sub _got_user_refresh {
  my ($session, $cgi, $cfg) = @_;

  my $baseurl = $cfg->entryVar('site', 'url');
  my $securl = $cfg->entryVar('site', 'secureurl');
  my $need_magic = $baseurl ne $securl;
  my $onbase = 1;
  if ($need_magic) {
    my $debug = $cfg->entryBool('debug', 'logon_cookies', 0);
    print STDERR "Logon Cookies Debug\n" if $debug;

    # which host are we on?
    # first get info about the 2 possible hosts
    my ($baseprot, $basehost, $baseport) = 
      $baseurl =~ m!^(\w+)://([\w.-]+)(?::(\d+))?!;
    $baseport ||= $baseprot eq 'http' ? 80 : 443;
    print STDERR "Base: prot: $baseprot  Host: $basehost  Port: $baseport\n"
      if $debug;

    #my ($secprot, $sechost, $secport) = 
    #  $securl =~ m!^(\w+)://([\w-.]+)(?::(\d+))?!;

    # get info about the current host
    my $port = $ENV{SERVER_PORT} || 80;
    my $ishttps = exists $ENV{HTTPS} || exists $ENV{SSL_CIPHER};
    print STDERR "\$ishttps: $ishttps\n" if $debug;
    my $protocol = $ishttps ? 'https' : 'http';

    if (lc $ENV{SERVER_NAME} ne lc $basehost
       || lc $protocol ne $baseprot
       || $baseport != $port) {
      $onbase = 0;
    }
  }
  my $refresh = $cgi->param('r');
  if ($need_magic) {
    my $url = $onbase ? $securl : $baseurl;
    my $finalbase = $onbase ? $baseurl : $securl;
    $refresh ||= "$ENV{SCRIPT_NAME}?userpage=1";
    $refresh = $finalbase . $refresh unless $refresh =~ /^\w+:/;
    $url .= "$ENV{SCRIPT_NAME}?setcookie=".$session->{_session_id};
    $url .= "&r=".CGI::escape($refresh);
    refresh_to($url);
  }
  else {
    if ($refresh) {
      refresh_to($refresh);
    }
    else {
      refresh_to($cfg->entryErr('site', 'url') . "$ENV{SCRIPT_NAME}?userpage=1");
    }
  }
}

sub set_cookie {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $cookie = $cgi->param('setcookie')
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(nocookie=>"No cookie provided"));
  my %newsession;
  BSE::Session->change_cookie($session, $cfg, $cookie, \%newsession);
  my $refresh = $cgi->param('r') 
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(norefresh=>"No refresh provided"));
  my $userid = $newsession{userid};
  if ($userid) {
    my $user = SiteUsers->getBy(userId => $userid);
    use CGI::Cookie;
    print "Set-Cookie: ",CGI::Cookie->new(-name=>"userid", 
					  -value=>$userid,
					  -path=>"/"),"\n";
  }
  refresh_to($refresh);
}

sub logoff {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $session->{userid}
    or return $self->show_logon($session, $cgi, $cfg, 
				$msgs->(notloggedon=>"You aren't logged on"));

  delete $session->{userid};
  print "Set-Cookie: ",CGI::Cookie->new(-name=>"userid", 
					-value=>'',
					-path=>"/"),"\n";
  return $self->show_logon($session, $cgi, $cfg);
}

sub show_register {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  $message ||= $cgi->param('message') || '';
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
     message => sub { CGI::escapeHTML($message) },
    );

  BSE::Template->show_page('user/register', $cfg, \%acts);
}

sub show_opts {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  my $userid = $session->{userid}
    or return $self->show_logon($session, $cgi, $cfg);
  my $user = SiteUsers->getBy(userId=>$userid)
    or return $self->show_logon($session, $cgi, $cfg);
  my @subs = grep $_->{visible}, BSE::SubscriptionTypes->all;
  my @usersubs = BSE::SubscribedUsers->getBy(userId=>$user->{id});
  my %usersubs = map { $_->{subId}, $_ } @usersubs;
  
  my $sub_index;
  $message ||= $cgi->param('message') || '';
  #use Data::Dumper;
  #print STDERR Dumper($user);
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
     message => sub { CGI::escapeHTML($message) },
     BSE::Util::Tags->make_iterator(\@subs, 'subscription', 'subscriptions',
				    \$sub_index),
     ifSubscribed=>sub { $usersubs{$subs[$sub_index]{id}} },
     ifAnySubs => sub { @usersubs },
    );

  BSE::Template->show_page('user/options', $cfg, \%acts);
}

sub saveopts {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');

  my $userid = $session->{userid};
  my $user;
  if ($userid) {
    $user = SiteUsers->getBy(userId=>$userid);
  }
  $user or return $self->show_logon($session, $cgi, $cfg, 
				    $msgs->(pleaselogon=>"Please logon"));
  my $oldpass = $cgi->param('old_password');
  my $newpass = $cgi->param('password');
  my $confirm = $cgi->param('confirm_password');

  if (defined $newpass && length $newpass) {
    $oldpass or
      return $self->show_opts($session, $cgi, $cfg,
			      $msgs->(optsoldpass=>"You need to enter your old password to change your password"));
    my $min_pass_length = $cfg->entry('basic', 'minpassword') || 4;
    my $error;
    if (length $newpass < $min_pass_length) {
      $error = $msgs->(optspasslen=>
		       "The password must be at least $min_pass_length characters",
		      $min_pass_length);
    }
    elsif (!defined $confirm || length $confirm == 0) {
      $error = $msgs->(optsconfpass=>"Please enter a confirmation password");
    }
    elsif ($newpass ne $confirm) {
      $error = $msgs->(optsconfmismatch=>"The confirmation password is different from the password");
    }
    
    $error and return $self->show_opts($session, $cgi, $cfg, $error);

    $user->{password} = $newpass;
  }
  my $email = $cgi->param('email');
  $email && length $email
    or return $self->show_opts($session, $cgi, $cfg,
			       $msgs->(optsnoemail=>
				       "Please enter an email address"));
  $email =~ /.@./
    or return $self->show_opts($session, $cgi, $cfg,
			       $msgs->(optsbademail=>
				       "Please enter a valid email address"));
  if ($email ne $user->{email}) {
    $user->{confirmed} = 0;
    $user->{confirmSecret} = '';
  }
  $user->{email} = $email;
  my @donttouch = qw(id userId password email confirmed confirmSecret waitingForConfirmation);
  my %donttouch = map { $_, $_ } @donttouch;
  my @cols = grep !$donttouch{$_}, SiteUser->columns;
  for my $col (@cols) {
    my $value = $cgi->param($col);
    if (defined $value) {
      $user->{$col} = $value;
    }
  }
  $user->{textOnlyMail} = 0 unless defined $cgi->param('textOnlyMail');
  $user->{keepAddress} = 0 unless defined $cgi->param('keepAddress');
  $user->save;

  # subscriptions
  my @subids = $cgi->param('subscription');
  $user->removeSubscriptions;
  if (@subids) {
    my @usersubs;
    my @subs;
    my @cols = BSE::SubscribedUser->columns;
    shift @cols; # don't set id
    for my $subid (@subids) {
      $subid =~ /^\d+$/ or next;
      my $sub = BSE::SubscriptionTypes->getByPkey($subid)
	or next;
      my %usersub;
      $usersub{subId} = $subid;
      $usersub{userId} = $user->{id};

      push(@usersubs, BSE::SubscribedUsers->add(@usersub{@cols}));
      push(@subs, $sub);
    }
    if (!$user->{confirmed}) {
      return $self->send_conf_request($session, $cgi, $cfg, $user,
				      \@usersubs, \@subs);
    }
  }
  refresh_to($cfg->entryErr('site', 'url') . "$ENV{SCRIPT_NAME}?userpage=1");
}

sub register {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $cgi->param('userid');
  if (!defined $userid || length $userid == 0) {
    return $self->show_register($session, $cgi, $cfg, 
				$msgs->(reguser=>"Please enter a userid"));
  }
  my $min_pass_length = $cfg->entry('basic', 'minpassword') || 4;
  my $pass = $cgi->param('password');
  my $pass2 = $cgi->param('confirm_password');
  my $email = $cgi->param('email');
  my $error;
  if (!defined $pass || length $pass == 0) {
    $error = $msgs->(regpass=>"Please enter a password");
  }
  elsif (length $pass < $min_pass_length) {
    $error = $msgs->(regpasslen=>"The password must be at least $min_pass_length characters");
  }
  elsif (!defined $pass2 || length $pass2 == 0) {
    $error = $msgs->(regconfpass=>"Please enter a confirmation password");
  }
  elsif ($pass ne $pass2) {
    $error = $msgs->(regconfmismatch=>"The confirmation password is different from the password");
  }
  elsif (!length $email) {
    $error = $msgs->(regnoemail => "Please enter an email address");
  }
  elsif ($email !~ /.\@./) {
    $error = $msgs->(regbademail => "Please enter a valid email address");
  }
  if ($error) {
    return $self->show_register($session, $cgi, $cfg, $error);
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
    return $self->show_register($session, $cgi, $cfg, 
				$msgs->(regexists=>
					"Sorry, user $userid already exists",
					$userid));
  }

  my %user;
  my @cols = SiteUser->columns;
  shift @cols;
  for my $field (@cols) {
    $user{$field} = '';
  }
  $user{userId} = $userid;
  $user{password} = $pass;
  $user{email} = $email;
  use BSE::Util::SQL qw/now_datetime/;
  $user{lastLogon} = $user{whenRegistered} = now_datetime;
  $user{keepAddress} = 0;
  $user{wantLetter} = 0;
  
  eval {
    $user = SiteUsers->add(@user{@cols});
  };
  if ($user) {
    $session->{userid} = $user->{userId};
    use CGI::Cookie;
    print "Set-Cookie: ",CGI::Cookie->new(-name=>"userid", 
					  -value=>$user->{userId},
					  -path=>"/"),"\n";
    use Util qw/refresh_to/;
    
    _got_user_refresh($session, $cgi, $cfg);
    
#      my $refresh = $cgi->param('r');
#      if ($refresh) {
#        refresh_to($refresh);
#      }
#      else {
#        return refresh_to($cfg->entryErr('site', 'url') . "/cgi-bin/user.pl?show_opts=1");
#      }
  }
  else {
    $self->show_register($session, $cgi, $cfg,
			 $msgs->(regdberr=>
				 "Database error $@"));
  }
}

sub userpage {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  my $userid = $session->{userid};
  my $user;
  if ($userid) {
    $user = SiteUsers->getBy(userId=>$userid);
  }
  $user or return $self->show_logon($session, $cgi, $cfg, "Please logon");
  require 'Orders.pm';
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate}
			|| $b->{id} <=> $a->{id} }
    Orders->getBy(userId=>$userid);
  $message ||= $cgi->param('message') || '';

  my $must_be_paid = $cfg->entryBool('downloads', 'must_be_paid', 0);
  my $must_be_filled = $cfg->entryBool('download', 'must_be_filled', 0);

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
       return 0 if $must_be_paid && !$orders[$order_index]{paidFor};
       return 0 if $must_be_filled && !$orders[$order_index]{filled};
       return 1;
     },
    );
  BSE::Template->show_page('user/userpage', $cfg, \%acts);
}

sub download {
  my ($self, $session, $cgi, $cfg) = @_;

  my $msgs = BSE::Message->new(cfg=>$cfg, section=>'user');
  my $userid = $session->{userid};
  my $user;
  if ($userid) {
    $user = SiteUsers->getBy(userId=>$userid);
  }
  $user or return $self->show_logon($session, $cgi, $cfg, 
				    $msgs->('pleaselogon', "Please logon"));

  my $orderid = $cgi->param('order')
    or return _refresh_userpage($cfg, $msgs->('noorderid', "No order id supplied"));
  require 'Orders.pm';
  my $order = Orders->getByPkey($orderid)
    or return _refresh_userpage($cfg, $msgs->('nosuchorder',
					"No such orderd $orderid", $orderid));
  unless (length $order->{userId}
	  && $order->{userId} eq $userid) {
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
  if ($must_be_paid && !$order->{paidFor}) {
    return _refresh_userpage($cfg, $msgs->("paidfor", 
				     "Order not marked as paid for"));
  }
  if ($must_be_filled && !$order->{filled}) {
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
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     message => sub { CGI::escapeHTML($message) },
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
  my $from = $cfg->entry('basic', 'emailfrom') || $SHOP_FROM;
  my $subject = $cfg->entry('basic', 'lostpasswordsubject') 
    || "Your password";
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
  my $black = BSE::EmailBlacklist->getEntry($genemail);
  if ($black) {
    BSE::Template->show_page('user/alreadyblacklisted', $cfg, \%acts);
    return;
  }
  my %black;
  my @cols = BSE::EmailBlackEntry->columns;
  shift @cols;
  $black{email} = $genemail;
  $black{why} = "HTTP request from $ENV{REMOTE_ADDR}";
  $black = BSE::EmailBlacklist->add(@cols);
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

sub send_conf_request {
  my ($self, $session, $cgi, $cfg, $user, $usersubs, $subs) = @_;

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
  
  my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);

  if ($blackentry) {
    $acts{black} = sub { CGI::escapeHTML($blackentry->{$_[0]}) },
    BSE::Template->show_page('user/blacklisted', $cfg, \%acts);
    return;
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
      return;
    }
    if ($too_soon) {
      BSE::Template->show_page('user/toosoon', $cfg, \%acts);
      return;
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
  my $body = BSE::Template->get_page('user/email_confirm', $cfg, \%confacts);
  
  my $mail = BSE::Mail->new(cfg=>$cfg);
  my $subject = $cfg->entry('confirmations', 'subject') 
    || 'Subscription Confirmation';
  my $from = $cfg->entry('confirmation', 'from') || $SHOP_FROM;
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
  BSE::Template->show_page('user/confsent', $cfg, \%acts);
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
