package SiteUser;
use strict;
# represents a registered user
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Constants qw($SHOP_FROM);
use BSE::Util::SQL qw/now_datetime now_sqldate sql_normal_date sql_add_date_days/;

use constant MAX_UNACKED_CONF_MSGS => 3;
use constant MIN_UNACKED_CONF_GAP => 2 * 24 * 60 * 60;

sub columns {
  return qw/id userId password email keepAddress whenRegistered lastLogon
            name1 name2 address city state postcode telephone facsimile 
            country wantLetter confirmed confirmSecret waitingForConfirmation
            textOnlyMail title organization referral otherReferral
            prompt otherPrompt profession otherProfession previousLogon
            billFirstName billLastName billStreet billSuburb billState 
            billPostCode billCountry instructions billTelephone billFacsimile 
            billEmail adminNotes disabled flags
            customText1 customText2 customText3
            customStr1 customStr2 customStr3
            affiliate_name/;
}

sub valid_fields {
  my ($class, $cfg, $admin) = @_;

  my %fields =
    (
     email => { rules=>'email;required', description=>'Email Address',
		maxlen => 255},
     name1 => { description=>'First Name', rules=>"dh_one_line", maxlen=>127 },
     name2 => { description=>'Surname', rules=>"dh_one_line", maxlen=>127 },
     address => { description => 'Address', rules=>"dh_one_line", maxlen=>127 },
     city => { description=>'City/Suburb', rules=>"dh_one_line", maxlen=>127 },
     state => { description => 'State', rules=>"dh_one_line", maxlen=>40 },
     postcode => { rules=>'postcode', description=>'Post Code', maxlen=>40 },
     telephone => { rules=>'phone', description=>'Telephone', maxlen=>80 },
     facsimile => { rules=>'phone', description=>'Facsimile', maxlen=>80 },
     country => { description=>'Country', rules=>"dh_one_line", maxlen=>127 },
     title => { description=>'Title', rules=>"dh_one_line", maxlen=>127  },
     organization => { description=>'Organization', rules=>"dh_one_line", 
		       maxlen=>127  },
     textOnlyEmail => { description => "Text Only Email", type=>"boolean" },
     referral => { description=>'Referral', rules=>"natural"  },
     otherReferral => { description=>'Other Referral', rules=>"dh_one_line",
		      maxlen=>127},
     prompt => { description=>'Prompt', rules=>"natural" },
     otherPrompt => { description => 'Other Prompt', rules=>"dh_one_line",
		    maxlen=>127 },
     profession => { description => 'Profession', rules=>"natural" },
     otherProfession => { description=>'Other Profession',
			  rules=>"dh_one_line", maxlen=>127 },
     billFirstName => { description=>"Billing First Name",
			rules=>"dh_one_line", maxlen=>127 },
     billLastName => { descriptin=>"Billing Last Name", rules=>"dh_one_line" },
     billStreet => { description => "Billing Street Address",
		     rules=>"dh_one_line", maxlen=>127 },
     billSuburb => { description => "Billing Suburb", rules=>"dh_one_line", 
		     maxlen=>127 },
     billState => { description => "Billing State", rules=>"dh_one_line", 
		    maxlen=>40 },
     billPostCode => { description => "Billing Post Code", rules=>"postcode", 
		       maxlen=>40 },
     billCountry => { description => "Billing Country", rules=>"dh_one_line", 
		      maxlen=>127 },
     instructions => { description => "Delivery Instructions" },
     billTelephone => { description => "Billing Phone", rules=>"phone", 
			maxlen=>80 },
     billFacsimile => { description => "Billing Facsimie", rules=>"phone", 
			maxlen=>80 },
     billEmail => { description => "Billing Email", rules=>"email", 
		    maxlen=>255 },
     customText1 => { description => "Custom Text 1" },
     customText2 => { description => "Custom Text 2" },
     customText3 => { description => "Custom Text 3" },
     customStr1 => { description => "Custom String 1", rules=>"dh_one_line",
		     maxlen=>255 },
     customStr2 => { description => "Custom String 2", rules=>"dh_one_line",
		     maxlen=>255 },
     customStr3 => { description => "Custom String 3", rules=>"dh_one_line",
		     maxlen=>255 },
    );

  if ($admin) {
    $fields{adminNotes} =
      { description => "Administrator Notes" };
    $fields{disabled} =
      { description => "User Disabled", type=>"boolean" };
  }

  for my $field_name (keys %fields) {
    $fields{$field_name}{required} ||= $cfg->entry("site users", "require_$field_name", 0);
    if (my $desc = $cfg->entry("site users", "display_$field_name")) {
      $fields{$field_name}{description} = $desc;
    }
  }

  return %fields;
}

sub valid_rules {
  return;
}

sub removeSubscriptions {
  my ($self) = @_;

  SiteUsers->doSpecial('removeSubscriptions', $self->{id});
}

sub removeSubscription {
  my ($self, $subid) = @_;

  SiteUsers->doSpecial('removeSub', $self->{id}, $subid);
}

sub generic_email {
  my ($class, $checkemail) = @_;

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

sub subscriptions {
  my ($self) = @_;

  require BSE::SubscriptionTypes;
  return BSE::SubscriptionTypes->getSpecial(userSubscribedTo => $self->{id});
}

sub send_conf_request {
  my ($user, $cgi, $cfg, $rcode, $rmsg) = @_;
      
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  
  # check for existing in-progress confirmations
  my $checkemail = $user->generic_email($user->{email});
  
  # check the blacklist
  require BSE::EmailBlacklist;

  # check that the from address has been configured
  my $from = $cfg->entry('confirmations', 'from') || 
    $cfg->entry('basic', 'emailfrom')|| $SHOP_FROM;
  unless ($from) {
    $$rcode = 'config';
    $$rmsg = "Configuration Error: The confirmations from address has not been configured";
    return;
  }

  my $blackentry = BSE::EmailBlacklist->getEntry($checkemail);

  if ($blackentry) {
    $$rcode = "blacklist";
    $$rmsg = $blackentry->{why};
    return;
  }
  
  unless ($user->{confirmSecret}) {
    use BSE::Util::Secure qw/make_secret/;
    # print STDERR "Generating secret\n";
    $user->{confirmSecret} = make_secret($cfg);
    $user->save;
  }

  # check for existing confirmations
  require BSE::EmailRequests;
  my $confirm = BSE::EmailRequests->getBy(genEmail=>$checkemail);
  if ($confirm) {
    if ($confirm->{unackedConfMsgs} >= MAX_UNACKED_CONF_MSGS) {
      $$rcode = 'toomany';
      $$rmsg = "Too many confirmations have been sent to this email address";
      return;
    }
    use BSE::Util::SQL qw/sql_datetime_to_epoch/;
    my $lastSentEpoch = sql_datetime_to_epoch($confirm->{lastConfSent});
    if ($lastSentEpoch + MIN_UNACKED_CONF_GAP > time) {
      $$rcode = 'toosoon';
      $$rmsg = "The last confirmation was sent too recently, please wait before trying again";
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
     BSE::Util::Tags->basic(\%confacts, $cgi, $cfg),
     user => sub { $user->{$_[0]} },
     confirm => sub { $confirm->{$_[0]} },
     remote_addr => sub { $ENV{REMOTE_ADDR} },
    );
  my $email_template = 
    $nopassword ? 'user/email_confirm_nop' : 'user/email_confirm';
  my $body = BSE::Template->get_page($email_template, $cfg, \%confacts);

  require BSE::Mail;
  my $mail = BSE::Mail->new(cfg=>$cfg);
  my $subject = $cfg->entry('confirmations', 'subject') 
    || 'Subscription Confirmation';
  unless ($mail->send(from=>$from, to=>$user->{email}, subject=>$subject,
		      body=>$body)) {
    # a problem sending the mail
    $$rcode = "mail";
    $$rmsg = $mail->errstr;
    return;
  }
  ++$confirm->{unackedConfMsgs};
  $confirm->{lastConfSent} = now_datetime;
  $confirm->save;

  return 1;
}

sub orders {
  my ($self) = @_;

  require BSE::TB::Orders;

  return BSE::TB::Orders->getBy(userId => $self->{userId});
}

sub _user_sub_entry {
  my ($self, $sub) = @_;

  my ($entry) = BSE::DB->query(userSubscribedEntry => $self->{id}, 
			       $sub->{subscription_id})
    or return;

  return $entry;
}

# check if the user is subscribed to the given subscription
sub subscribed_to {
  my ($self, $sub) = @_;

  my $entry = $self->_user_sub_entry($sub)
    or return;

  my $today = now_sqldate;
  my $end_date = sql_normal_date($entry->{ends_at});
  return $today le $end_date;
}

# check if the user is subscribed to the given subscription, and allow
# for the max_lapsed grace period
sub subscribed_to_grace {
  my ($self, $sub) = @_;

  my $entry = $self->_user_sub_entry($sub)
    or return;

  my $today = now_sqldate;
  my $end_date = sql_add_date_days($entry->{ends_at}, $entry->{max_lapsed});
  return $today le $end_date;
}

my @image_cols = 
  qw(siteuser_id image_id filename width height bytes content_type alt);

sub images_cfg {
  my ($self, $cfg) = @_;

  my @images;
  my %ids = $cfg->entries('BSE Siteuser Images');
  for my $id (keys %ids) {
    my %image = ( id => $id );

    my $sect = "BSE Siteuser Image $id";
    for my $key (qw(description help minwidth minheight maxwidth maxheight
                    minratio maxratio properror 
                    widthsmallerror heightsmallerror smallerror
                    widthlargeerror heightlargeerror largeerror
                    maxspace spaceerror)) {
      my $value = $cfg->entry($sect, $key);
      if (defined $value) {
	$image{$key} = $value;
      }
    }
    push @images, \%image;
  }
  
  @images;
}

sub images {
  my ($self) = @_;

  BSE::DB->query(getBSESiteuserImages => $self->{id});
}

sub get_image {
  my ($self, $id) = @_;

  my ($image) = BSE::DB->query(getBSESiteuserImage => $self->{id}, $id)
    or return;

  $image;
}

sub set_image {
  my ($self, $cfg, $id, $image) = @_;

  my %image = %$image;
  $image{siteuser_id} = $self->{id};
  my $old = $self->get_image($id);

  if ($old) {
    # replace it
    BSE::DB->run(replaceBSESiteuserImage => @image{@image_cols});

    # lose the old file
    my $image_dir = $cfg->entryVar('paths', 'siteuser_images');
    unlink "$image_dir/$old->{filename}";
  }
  else {
    # add it
    # replace it
    BSE::DB->run(addBSESiteuserImage => @image{@image_cols});
  }
}

sub remove_image {
  my ($self, $cfg, $id) = @_;

  if (my $old = $self->get_image($id)) {
    # remove the entry
    BSE::DB->run(deleteBSESiteuserImage => $self->{id}, $id);
    
    # lose the old file
    my $image_dir = $cfg->entryVar('paths', 'siteuser_images');
    unlink "$image_dir/$old->{filename}";
  }
}

sub recalculate_subscriptions {
  my ($self, $cfg) = @_;

  require BSE::TB::Subscriptions;
  my @subs = BSE::TB::Subscriptions->all;
  for my $sub (@subs) {
    $sub->update_user_expiry($self, $cfg);
  }
}

sub subscribed_services {
  my ($self) = @_;

  BSE::DB->query(siteuserSubscriptions => $self->{id});
}

1;
