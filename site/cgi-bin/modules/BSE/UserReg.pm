package BSE::UserReg;
use strict;
use SiteUsers;
use BSE::Util::Tags;
use BSE::Template;
use Constants qw($URLBASE $SHOP_FROM);
use BSE::Message;

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
     ifUser=> sub { $user },
     user => sub { $user && CGI::escapeHTML($user->{$_[0]}) },
    );
}

sub show_logon {
  my ($self, $session, $cgi, $cfg, $message) = @_;

  $message ||= $cgi->param('message') || '';
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts),
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

  refresh_to("$URLBASE$ENV{SCRIPT_NAME}?userpage=1");
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
     BSE::Util::Tags->basic(\%acts),
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
  
  $message ||= $cgi->param('message') || '';
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts),
     $self->user_tags(\%acts, $session, $user),
     last => 
     sub {
       my $value = $cgi->param($_[0]);
       defined $value or $value = $user->{$_[0]};
       defined $value or $value = '';
       CGI::escapeHTML($value);
     },
     message => sub { CGI::escapeHTML($message) },
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
  $user->{email} = $email;
  my @donttouch = qw(id userId password email);
  my %donttouch = map { $_, $_ } @donttouch;
  my @cols = grep !$donttouch{$_}, SiteUser->columns;
  for my $col (@cols) {
    my $value = $cgi->param($col);
    if (defined $value) {
      $user->{$col} = $value;
    }
  }
  $user->save;
  refresh_to("$URLBASE$ENV{SCRIPT_NAME}?userpage=1");
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
    
    return refresh_to("$URLBASE/cgi-bin/user.pl?show_opts=1");
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
  my @orders = sort { $b->{orderDate} cmp $a->{orderDate} }
    Orders->getBy(userId=>$userid);

  my $order_index;
  my $item_index;
  my @items;
  my %acts;
  my $product;
  my @files;
  my $file_index;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts),
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
     make_dependent_iterator
     (\$file_index,
      sub {
	require 'ArticleFiles.pm';
	@files = sort { $b->{displayOrder} <=> $a->{displayOrder} }
	  ArticleFiles->getBy(articleId=>$items[$item_index]{productId});
      },
      'prodfile', 'prodfiles', \$file_index),
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
    or return $self->userpage($session, $cgi, $cfg,
			      $msgs->('noorderid', "No order id supplied"));
  require 'Orders.pm';
  my $order = Orders->getByPkey($orderid)
    or return $self->userpage($session, $cgi, $cfg,
			      $msgs->('nosuchorder',
				      "No such orderd $orderid", $orderid));
  unless (length $order->{userId}
	  && $order->{userId} eq $userid) {
    return $self->userpage($session, $cgi, $cfg,
			   $msgs->("notyourorder",
				   "Order $orderid isn't yours", $orderid));
  }
  my $itemid = $cgi->param('item')
    or return $self->userpage($session, $cgi, $cfg,
			      $msgs->('noitemid', "No item id supplied"));
  require 'OrderItems.pm';
  my ($item) = grep $_->{id} == $itemid,
  OrderItems->getBy(orderId=>$order->{id})
    or return $self->userpage($session, $cgi, $cfg,
			      $msgs->(notinorder=>"Not part of that order"));
  require 'ArticleFiles.pm';
  my @files = ArticleFiles->getBy(articleId=>$item->{productId})
    or return $self->userpage($session, $cgi, $cfg,
			      $msgs->(nofilesonline=>"No files in this line"));
  my $fileid = $cgi->param('file')
    or return $self->userpage($session, $cgi, $cfg,
			      $msgs->(nofileid=>"No file id supplied"));
  my ($file) = grep $_->{id} == $fileid, @files
    or return $self->userpage($session, $cgi, $cfg,
			      $msgs->(nosuchfile=>"No such file in that line item"));
  
  my $must_be_paid = $cfg->entry('downloads', 'must_be_paid');
  my $must_be_filled = $cfg->entry('download', 'must_be_filled');
  if ($must_be_paid && !$order->{paidFor}) {
    return $self->userpage($session, $cgi, $cfg,
			   $msgs->("paidfor", 
				   "Order not marked as paid for"));
  }
  if ($must_be_filled && !$order->{filled}) {
    return $self->userpage($session, $cgi, $cfg,
			   $msgs->("filled", 
				   "Order not marked as filled"));
  }
  
  my $filebase = $cfg->entryVar('paths', 'downloads');
  open FILE, "< $filebase/$file->{filename}"
    or return $self->
      userpage($session, $cgi, $cfg,
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
     BSE::Util::Tags->basic(\%acts),
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

  my $mail = BSE::Mail->new;

  my %mailacts;
  %mailacts =
    (
     user => sub { $user->{$_[0]} },
     host => sub { $ENV{REMOTE_ADDR} },
     site => sub { $URLBASE },
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
     BSE::Util::Tags->basic(\%acts),
     user => sub { CGI::escapeHTML($user->{$_[0]}) },
    );
  BSE::Template->show_page('user/lostemailsent', $cfg, \%acts);
}

1;
