package SiteUser;
use strict;
# represents a registered user
use Squirrel::Row;
use vars qw/@ISA/;
@ISA = qw/Squirrel::Row/;
use Constants qw($SHOP_FROM);
use BSE::Util::SQL qw/now_datetime/;

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
            billEmail adminNotes disabled flags/;
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

1;
