package SiteUser;
use strict;
# represents a registered user
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Constants qw($SHOP_FROM);
use Carp qw(confess);
use BSE::Util::SQL qw/now_datetime now_sqldate sql_normal_date sql_add_date_days/;

our $VERSION = "1.006";

use constant MAX_UNACKED_CONF_MSGS => 3;
use constant MIN_UNACKED_CONF_GAP => 2 * 24 * 60 * 60;
use constant OWNER_TYPE => "U";

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
            affiliate_name delivMobile billMobile
            delivStreet2 billStreet2
            billOrganization
            customInt1 customInt2 password_type
            lost_today lost_date lost_id/;
}

sub table {
  return "site_users";
}

sub defaults {
  require BSE::Util::SQL;
  return
    (
     keepAddress => 1, # what am I for - appears unused
     whenRegistered => BSE::Util::SQL::now_datetime(),
     lastLogon => BSE::Util::SQL::now_datetime(),
     name1 => "",
     name2 => "",
     address => "",
     city => "",
     state => "",
     postcode => "",
     telephone => "",
     facsimile => "",
     country => "",
     wantLetter => 0, # also unused
     confirmed => 0,
     confirmSecret => "",
     waitingForConfirmation => 0,
     textOnlyMail => 0,
     title => "",
     organization => "",
     referral => 0,
     otherReferral => "",
     prompt => 0,
     otherPrompt => "",
     profession => 0,
     otherProfession => "",
     previousLogon => BSE::Util::SQL::now_datetime(),
     billFirstName => "",
     billLastName => "",
     billStreet => "",
     billSuburb => "",
     billState => "", 
     billPostCode => "",
     billCountry => "",
     instructions => "",
     billTelephone => "",
     billFacsimile => "", 
     billEmail => "",
     adminNotes => "",
     disabled => 0,
     flags => "",
     customText1 => undef,
     customText2 => undef,
     customText3 => undef,
     customStr1 => undef,
     customStr2 => undef,
     customStr3 => undef,
     affiliate_name => "",
     delivMobile => "",
     billMobile => "",
     delivStreet2 => "",
     billStreet2 => "",
     billOrganization => "",
     customInt1 => "",
     customInt2 => "",
     #password_type,
     lost_today => 0,
     lost_date => undef,
     lost_id => undef,
    );
}

sub valid_fields {
  my ($class, $cfg, $admin) = @_;

  my %fields =
    (
     email => { rules=>'email', description=>'Email Address',
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
     delivMobile => { description => "Mobile", rules=>"phone",
		      maxlen => 80 },
     delivStreet2 => { description => 'Address2', rules => "dh_one_line",
		       maxlen=> 127 },
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
     billStreet2 => { description => 'Billing Street Address 2', 
		      rules => "dh_one_line", maxlen=> 127 },
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
     billMobile => { description => "Billing Mobile", rules=>"phone",
		     maxlen => 80 },
     billOrganization => { description => "Billing Organization",
			   rules=>"dh_one_line", maxlen => 127 },
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

  if ($user->is_disabled) {
    $$rmsg = "User is disabled";
    return;
  }
      
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

sub is_disabled {
  my ($self) = @_;

  return $self->{disabled};
}

sub seminar_sessions_booked {
  my ($self, $seminar_id) = @_;

  return map $_->{session_id}, 
    BSE::DB->query(userSeminarSessionBookings => $seminar_id, $self->{id});
}

sub is_member_of {
  my ($self, $group) = @_;

  my $group_id = ref $group ? $group->{id} : $group;

  my @result = BSE::DB->query(siteuserMemberOfGroup => $self->{id}, $group_id);

  return scalar(@result);
}

sub group_ids {
  my ($self) = @_;

  map $_->{id}, BSE::DB->query(siteuserGroupsForUser => $self->{id});
}

sub allow_html_email {
  my ($self) = @_;

  !$self->{textOnlyMail};
}

sub seminar_bookings_detail {
  my ($self) = @_;

  BSE::DB->query(bse_siteuserSeminarBookingsDetail => $self->{id});
}

sub wishlist {
  my $self = shift;
  require Products;
  return Products->getSpecial(userWishlist => $self->{id});
}

sub wishlist_order {
  my $self = shift;
  return BSE::DB->query(bse_userWishlistOrder => $self->{id});
}

sub product_in_wishlist {
  my ($self, $product) = @_;

  grep $_->{product_id} == $product->{id}, $self->wishlist_order;
}

sub add_to_wishlist {
  my ($self, $product) = @_;

  return 
    eval {
      BSE::DB->run(bse_addToWishlist => $self->{id}, $product->{id}, time());
      1;
    };
}

sub remove_from_wishlist {
  my ($self, $product) = @_;

  BSE::DB->run(bse_removeFromWishlist => $self->{id}, $product->{id});
}

sub _set_wishlist_order {
  my ($self, $product_id, $display_order) = @_;

  print STDERR "_set_wishlist_order($product_id, $display_order)\n";

  BSE::DB->run(bse_userWishlistReorder => $display_order, $self->{id}, $product_id);
}

sub _find_in_wishlist {
  my ($self, $product_id) = @_;

  my @order = $self->wishlist_order;

  my ($index) = grep $order[$_]{product_id} == $product_id, 0 .. $#order
    or return;

  return \@order, $index;
}

sub move_to_wishlist_top {
  my ($self, $product) = @_;

  my ($order, $move_index) = $self->_find_in_wishlist($product->{id})
    or return;
  $move_index > 0
    or return; # nothing to do

  my $top_order = $order->[0]{display_order};
  for my $index (0 .. $move_index-1) {
    $self->_set_wishlist_order($order->[$index]{product_id}, $order->[$index+1]{display_order});
  }
  $self->_set_wishlist_order($product->{id}, $top_order);
}

sub move_to_wishlist_bottom {
  my ($self, $product) = @_;

  my ($order, $move_index) = $self->_find_in_wishlist($product->{id})
    or return;
  $move_index < $#$order
    or return; # nothing to do

  my $bottom_order = $order->[-1]{display_order};
  for my $index (reverse($move_index+1 .. $#$order)) {
    $self->_set_wishlist_order($order->[$index]{product_id}, $order->[$index-1]{display_order});
  }
  $self->_set_wishlist_order($product->{id}, $bottom_order);
}

sub move_down_wishlist {
  my ($self, $product) = @_;

  my ($order, $index) = $self->_find_in_wishlist($product->{id})
    or return;
  $index < $#$order
    or return; # nothing to do

  $self->_set_wishlist_order($product->{id}, $order->[$index+1]{display_order});
  $self->_set_wishlist_order($order->[$index+1]{product_id}, $order->[$index]{display_order});
}

sub move_up_wishlist {
  my ($self, $product) = @_;

  my ($order, $index) = $self->_find_in_wishlist($product->{id})
    or return;
  $index > 0
    or return; # nothing to do

  $self->_set_wishlist_order($product->{id}, $order->[$index-1]{display_order});
  $self->_set_wishlist_order($order->[$index-1]{product_id}, $order->[$index]{display_order});
}

# files owned specifically by this user
sub files {
  my ($self) = @_;

  require BSE::TB::OwnedFiles;
  return BSE::TB::OwnedFiles->getBy(owner_type => OWNER_TYPE,
				    owner_id => $self->id);
}

sub admin_group_files {
  my ($self) = @_;

  require BSE::TB::OwnedFiles;
  return BSE::TB::OwnedFiles->getSpecial(userVisibleGroupFiles => $self->{id});
}

sub query_group_files {
  my ($self, $cfg) = @_;

  require BSE::TB::SiteUserGroups;
  return
    (
     map $_->files, BSE::TB::SiteUserGroups->query_groups($cfg)
    );
}

# files the user can see, both owned and owned by groups
sub visible_files {
  my ($self, $cfg) = @_;

  return
    (
     $self->files,
     $self->admin_group_files,
     $self->query_group_files($cfg)
    );
}

sub file_owner_type {
  return OWNER_TYPE;
}

sub subscribed_file_categories {
  my ($self) = @_;

  return map $_->{category}, BSE::DB->query(siteuserSubscribedFileCategories => $self->{id});
}

sub set_subscribed_file_categories {
  my ($self, $cfg, @new) = @_;

  require BSE::TB::OwnedFiles;
  my %current = map { $_ => 1 } $self->subscribed_file_categories;
  my %new = map { $_ => 1 } @new;
  my @all = BSE::TB::OwnedFiles->categories($cfg);
  for my $cat (@all) {
    if ($new{$cat->{id}} && !$current{$cat->{id}}) {
      eval {
	BSE::DB->run(siteuserAddFileCategory => $self->{id}, $cat->{id});
      }; # a race condition might cause a duplicate key error here
    }
    elsif (!$new{$cat->{id}} && $current{$cat->{id}}) {
      BSE::DB->run(siteuserRemoveFileCategory => $self->{id}, $cat->{id});
    }
  }
}

=item describe

Returns a description of the user

=cut

sub describe {
  my ($self) = @_;

  return "Member: " . $self->userId;
}

=item paid_files

Files that require payment that the user has paid for.

=cut

sub paid_files {
  my ($self) = @_;

  require BSE::TB::ArticleFiles;
  return BSE::TB::ArticleFiles->getSpecial(userPaidFor => $self->id);
}

sub remove {
  my ($self, $cfg) = @_;

  $cfg or confess "Missing parameter cfg";

  # remove any owned files
  for my $file ($self->files) {
    $file->remove($cfg);
  }

  # file subscriptions
  BSE::DB->run(bseRemoveUserFileSubs => $self->id);

  # file notifies
  BSE::DB->run(bseRemoveUserFileNotifies => $self->id);

  # download log
  BSE::DB->run(bseMarkUserFileAccessesAnon => $self->id);

  # mark any orders owned by the user as anonymous
  BSE::DB->run(bseMarkOwnedOrdersAnon => $self->id);

  # newsletter subscriptions
  BSE::DB->run(bseRemoveUserSubs => $self->id);

  # wishlist
  BSE::DB->run(bseRemoveUserWishlist => $self->id);

  # group memberships
  BSE::DB->run(bseRemoveUserMemberships => $self->id);

  # seminar bookings
  BSE::DB->run(bseRemoveUserBookings => $self->id);

  # paid subscriptions
  BSE::DB->run(bseRemoveUserProdSubs => $self->id);

  # images
  for my $im ($self->images) {
    $self->remove_image($cfg, $im->{image_id});
  }

  $self->SUPER::remove();
}

sub link {
  my ($self) = @_;

  return BSE::Cfg->single->admin_url(siteusers => { a_edit => 1, id => $self->id });
}

=item send_registration_notify(remote_addr => $ip_address)

Send an email to the customer with registration information.

Template: user/email_register

Basic static tags and:

=over

=item *

host - IP address of the machine that registered the user.

=item *

user - the user registered.

=back

=cut

sub send_registration_notify {
  my ($self, %opts) = @_;

  defined $opts{remote_addr}
    or confess "Missing remote_addr parameter";

  require BSE::ComposeMail;
  require BSE::Util::Tags;
  BSE::ComposeMail->send_simple
      (
       id => 'notify_register_customer', 
       template => 'user/email_register',
       subject => 'Thank you for registering',
       to => $self,
       extraacts =>
       {
	host => $opts{remote_addr},
	user => [ \&BSE::Util::Tags::tag_hash_plain, $self ],
       },
       log_msg => "Registration email to " . $self->email,
       log_component => "member:register:notifyuser",
      );
}

sub changepw {
  my ($self, $password, $who, %log) = @_;

  require BSE::Passwords;

  my ($hash, $type) = BSE::Passwords->new_password_hash($password);

  $self->set_password($hash);
  $self->set_password_type($type);

  require BSE::TB::AuditLog;
  BSE::TB::AuditLog->log
      (
       component => "siteusers::changepw",
       object => $self,
       actor => $who,
       level => "info",
       msg => "Change password",
       %log,
      );

  1;
}

sub check_password {
  my ($self, $password, $error) = @_;

  require BSE::Passwords;
  return BSE::Passwords->check_password_hash($self->password, $self->password_type, $password, $error);
}

=item lost_password

Call to send a lost password email.

=cut

sub lost_password {
  my ($self, $error) = @_;

  my $cfg = BSE::Cfg->single;
  require BSE::CfgInfo;
  my $custom = BSE::CfgInfo::custom_class($cfg);
  my $email_user = $self;
  my $to = $self;
  if ($custom->can('send_user_email_to')) {
    eval {
      $email_user = $custom->send_user_email_to($self, $cfg);
    };
    $to = $email_user->{email};
  }
  else {
    require BSE::Util::SQL;
    my $lost_limit = $cfg->entry("lost password", "daily_limit", 3);
    my $today = BSE::Util::SQL::now_sqldate();
    my $lost_today = 0;
    if ($self->lost_date
	&& $self->lost_date eq $today) {
      $lost_today = $self->lost_today;
    }
    if ($lost_today+1 > $lost_limit) {
      $$error = "Too many password recovery attempts today, please try again tomorrow";
      return;
    }
    $self->set_lost_date($today);
    $self->set_lost_today($lost_today+1);
    $self->set_lost_id(BSE::Util::Secure::make_secret($cfg));
  }

  require BSE::ComposeMail;
  my $mail = BSE::ComposeMail->new(cfg => $cfg);

  require BSE::Util::Tags;
  my %mailacts;
  %mailacts =
    (
     BSE::Util::Tags->mail_tags(),
     user => [ \&BSE::Util::Tags::tag_object_plain, $self ],
     host => $ENV{REMOTE_ADDR},
     site => $cfg->entryErr('site', 'url'),
     emailuser => [ \&BSE::Util::Tags::tag_hash_plain, $email_user ],
    );
  my $from = $cfg->entry('confirmations', 'from') || 
    $cfg->entry('basic', 'emailfrom') || $SHOP_FROM;
  my $nopassword = $cfg->entryBool('site users', 'nopassword', 0);
  my $subject = $cfg->entry('basic', 'lostpasswordsubject') 
    || ($nopassword ? "Your options" : "Your password");
  unless ($mail->send
	  (
	   template => 'user/lostpwdemail',
	   acts => \%mailacts,
	   from=>$from,
	   to => $to,
	   subject=>$subject,
	   log_msg => "Sending lost password recovery email",
	   log_component => "siteusers:lost:send",
	   log_object => $self,
	  )) {
    $$error = $mail->errstr;
    return;
  }
  $self->save;

  return $email_user;
}

sub check_password_rules {
  my ($class, $password, $error) = @_;

  my $cfg = BSE::Cfg->single;
  my $min_pass_length = $cfg->entry('basic', 'minpassword') || 4;
  if (length $password < $min_pass_length) {
    $$error = [ "passwordlen", $min_pass_length ];
    return;
  }

  return 1;
}

1;
