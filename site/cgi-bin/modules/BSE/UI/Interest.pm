package BSE::UI::Interest;
use strict;
use base 'BSE::UI::Dispatch';
use BSE::ComposeMail;
use BSE::TB::Products;
use BSE::Util::Tags qw(tag_object);

our $VERSION = "1.002";

my %actions =
  (
   default => 1,
   form => 1,
   interest => 1,
  );

sub actions { \%actions };

sub default_action { "default" }

sub req_default {
  my ($self, $req) = @_;

  my $email = $req->cgi->param('email');
  if ($email =~ /\S/) {
    return $self->req_interest($req);
  }
  else {
    return $self->req_form($req);
  }
}

sub req_form {
  my ($self, $req, $errors) = @_;

  $errors ||= {};
  $req->message($errors);

  my $cgi = $req->cgi;
  my $product_id = $cgi->param('product_id');
  defined($product_id)
    or return $self->error($req, { error => "msg:bse/interest/noproductid" });
  my $product = BSE::TB::Products->getByPkey($product_id)
    or return $self->error($req, { error => [ "msg:bse/interest/badproductid", $product_id ] });

  my $email = $cgi->param('email');
  unless (defined $email && $email =~ /\S/) {
    if ($req->siteuser) {
      $email = $req->siteuser->email;
    }
    else {
      $email = '';
    }
  }

  $req->set_variable(product => $product);
  $req->set_variable(email => $email);
  $req->set_variable(errors => $errors);
  my %acts =
    (
     $req->dyn_user_tags,
     email => $email,
    );

  return $req->response('interest/askagain', \%acts);
}

sub req_interest {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;;
  my $cgi = $req->cgi;

  my $product_id = $cgi->param('product_id');
  defined($product_id)
    or return $self->error($req, { error => "msg:bse/interest/noproductid" });
  my $product = BSE::TB::Products->getByPkey($product_id)
    or return $self->error($req, { error => [ "msg:bse/interest/badproductid", $product_id ] });

  my %errors;
  my $useremail = $cgi->param('email');
  if (!defined $useremail || $useremail !~ /\S/) {
    $errors{email} = "msg:bse/interest/noemail";
  }
  elsif ($useremail !~ /^[^\s\@][^\@]*\@[\w.-]+\.\w+$/) {
    $errors{email} = "msg:bse/interest/bademail";
  }

  %errors
    and return $self->req_form($req, \%errors);

  # in theory we have an email address at this point
  my $mailer = BSE::ComposeMail->new(cfg => $cfg);

  my $email = $cfg->entry('interest', 'notify');
  $email ||= $cfg->entry('shop', 'from', $Constants::SHOP_FROM);
  unless ($email) {
    print STDERR "No email configured for interest notify, set [interest].notify\n";
    return;
  }

  $req->set_variable(email => $useremail);
  $req->set_variable(product => $product);
  $req->set_variable(product_id => $product_id);

  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     product => [ \&tag_object, $product ],
     product_id => $product_id,
     email => $useremail,
    );

  my $subject = "User registered interest";
  $subject .= " in product '" . $product->title . "'";

  my %vars =
    (
     product => $product,
     email => $email,
     siteuser => $req->siteuser,
    );
  unless ($mailer->send
	  (
	   template => 'admin/interestemail',
	   acts => \%acts,
	   to=>$email,
	   from=>$email,
	   subject=>$subject,
	   vars => \%vars
	  )) {
    return $self->error($req, "While sending email: ".$mailer->errstr);
  }

  return $req->response('interest/confirm', \%acts);
}

1;
