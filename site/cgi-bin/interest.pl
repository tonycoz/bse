#!/usr/bin/perl -w
# -d:ptkdb
#BEGIN { $ENV{DISPLAY} = '192.168.32.97:0.0'; }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use Constants qw(:shop);
use BSE::Cfg;
use BSE::Session;
use BSE::Mail;
use BSE::Template;
use BSE::Util::Tags;
use SiteUsers;
use CGI;

my $cfg = BSE::Cfg->new;

my %session;
BSE::Session->tie_it(\%session, $cfg);

my $cgi = CGI->new;
my $useremail = $cgi->param('email');
unless ($useremail) {
  if ($session{userid}) {
    my $user = SiteUsers->getBy(userId=>$session{userid});
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
my $mailer = BSE::Mail->new(cfg=>$cfg);
my $sendto = $cfg->entry('interest', 'notify', $SHOP_FROM);
my $product = $cgi->param('product');
defined($product) or $product = '';
my $product_id = $cgi->param('product_id');
defined($product_id) or $product_id = '';

my %acts;
%acts =
  (
   BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
   product => sub { $product },
   product_id => sub { $product_id },
   email => sub { $useremail },
  );

my $content = BSE::Template->get_page('admin/interestemail', $cfg, \%acts);

my $subject = "User registered interest";
$subject .= " in product '$product'" if $product;
if ($content =~ s/^subject:\s+([^\n])\r?\n\r?//i) {
  $subject = $1;
}

$mailer->send(to=>$sendto, from=>$SHOP_FROM, subject=>$subject, 
	      body => $content)
  or error_page('', "While sending email: ".$mailer->errstr);

BSE::Template->show_page('interest/confirm', $cfg, \%acts);

sub error_page {
  my ($id, $msg, $template) = @_;

  $msg = $cfg->entry(messages=>$id, $msg) if $id;
  $template ||= 'interest/error';
  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(\%acts, $cgi, $cfg),
     msg => sub { CGI::escapeHTML($msg) },
    );
  BSE::Template->show_page($template, $cfg, \%acts);
  exit;
}