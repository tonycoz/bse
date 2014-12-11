package BSE::UI::Interest;
use strict;
use base 'BSE::UI::Dispatch';
use BSE::ComposeMail;

our $VERSION = "1.000";

my %actions =
  (
   interest => 1,
  );

sub actions { \%actions };

sub default_action { "interest" }

sub req_interest {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;;

  my $cgi = $req->cgi;
  my $useremail = $cgi->param('email');
  unless ($useremail) {
    my $user = $req->siteuser;
    if ($user) {
      $useremail = $user->{email};
    }
  }
  unless ($useremail) {
    my $msg = $req->catmsg("msg:bse/interest/noemail", [],
			  "Please enter an email address, register or logon");
    return $self->error($req, $msg, "interest/askagain");
  }

  if ($useremail !~ /.\@./) {
    my $msg = $req->catmsg("msg:bse/interest/bademail", [],
			  "Please enter a valid email address.");
    return $self->error($req, $msg, "interest/askagain");
  }

  # in theory we have an email address at this point
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);

  my $email = $cfg->entry('interest', 'notify');
  $email ||= $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
  unless ($email) {
    print STDERR "No email configured for interest notify, set [interest].notify\n";
    return;
  }
#
  my $product = $cgi->param('product');
  defined($product) or $product = '';
  my $product_id = $cgi->param('product_id');
  defined($product_id) or $product_id = '';

  $req->set_variable(email => $useremail);
  $req->set_variable(product => $product);
  $req->set_variable(product_id => $product_id);

  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     product => sub { $product },
     product_id => sub { $product_id },
     email => sub { $useremail },
    );

  my $subject = "User registered interest";
  $subject .= " in product '$product'" if $product;

  unless ($mailer->send(template => 'admin/interestemail',
			acts => \%acts,
			to=>$email,
			from=>$email,
			subject=>$subject)) {
    return $self->error($req, "While sending email: ".$mailer->errstr);
  }

  return $req->response('interest/confirm', \%acts);
}

1;
