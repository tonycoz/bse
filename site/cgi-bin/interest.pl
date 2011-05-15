#!/usr/bin/perl -w
# -d:ptkdb
#BEGIN { $ENV{DISPLAY} = '192.168.32.97:0.0'; }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use Constants qw(:shop);
use BSE::Session;
use BSE::Template;
use BSE::Util::Tags;
use BSE::Request;

my $req = BSE::Request->new;
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
  error_page("interest/noemail",
	     "Please enter an email address, register or logon",
	     'interest/askagain');
}
if ($useremail !~ /.\@./) {
  error_page("interest/bademail",
	     "Please enter a valid email address.",
	     'interest/askagain');
}

# in theory we have an email address at this point
require BSE::ComposeMail;
my $mailer = BSE::ComposeMail->new(cfg => $cfg);

my $email = $cfg->entry('interest', 'notify', 
			  $Constants::SHOP_FROM);
$email ||= $cfg->entry('shop', 'from');
unless ($email) {
  print STDERR "No email configured for interest notify, set [interest].notify\n";
  return;
}
#
my $product = $cgi->param('product');
defined($product) or $product = '';
my $product_id = $cgi->param('product_id');
defined($product_id) or $product_id = '';

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

$mailer->send(template => 'admin/interestemail',
    acts => \%acts,
    to=>$email,
    from=>$email,
    subject=>$subject)
  or error_page('', "While sending email: ".$mailer->errstr);

BSE::Template->show_page('interest/confirm', $cfg, \%acts);

sub error_page {
  my ($id, $msg, $template) = @_;

  $msg = $cfg->entry(messages=>$id, $msg) if $id;
  $template ||= 'interest/error';
  my %acts;
  %acts =
    (
     $req->dyn_user_tags,
     msg => sub { CGI::escapeHTML($msg) },
    );
  BSE::Template->show_page($template, $cfg, \%acts);
  exit;
}
