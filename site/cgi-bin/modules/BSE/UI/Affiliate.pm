package BSE::UI::Affiliate;
use strict;

use base qw(BSE::UI::Dispatch);

my %actions =
  (
   setaff => 1,
   show => 1,
   none => 1,
  );

sub actions { \%actions }

sub default_action { 'none' }

sub req_setaff {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cgi = $req->cfg;
  my $id = $cgi->param('id');

  defined($id) && $id =~ /^\w+$/
    or return $class->req_none($req, "Missing or invalid id");

  my $allowed_referer = $cfg->entry('affiliate', 'allowed_referer');
  my $require_referer = $cfg->entry('affiliate', 'require_referer');
  if ($allowed_referer) {
    my @allowed = split /;/, $allowed_referer;
    my $referer = $ENV{HTTP_REFERER};
    if ($referer) {
      my ($domain) = ($referer =~ m!^\w+://([\w/]+)!);
      $domain = lc $domain;
      my $found = 0;
      for my $entry (@allowed) {
	$entry = lc $entry;

	if ($length($entry) < $domain &&
	    $entry eq substr($domain, -length($entry))) {
	  ++$found;
	  last;
	}
      }
      $found
	or return $class->req_none($req, "$domain not in the permitted list of referers");
    }
    else {
      $require_referer
	and return $class->req_none($req, 'Referer not supplied');
    }
  }

  my $url = $cgi->param('r');
  $url ||= $cgi->entry('affiliate', 'default_refresh');
  $url ||= $cgi->entryVar('site', 'url');

  $req->session->{affiliate_code} = $id;

  return BSE::Template->get_refresh($url, $cfg);
}

# display the affiliate page for a given user
# this doesn't set the affiliate code (should it?)
sub req_show {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;

  my $id = $cgi->param('id');
  defined $id
    or return $class->req_none($req, "No identifier supplied");
  require SiteUsers;
  require BSE::TB::Subscriptions;
  my $user = SiteUsers->getBy(userId => $id);
  $user
    or return $class->req_none($req, "Unknown user");
  my $subid = $cfg->entry('affiliate', 'subscription_required');
  if ($subid) {
    my $sub = BSE::TB::Subscriptions->getByPkey($subid)
      || BSE::TB::Subscriptions->getBy(text_id => $subid)
	or return $class->req_none($req, "Configuration error: Unknown subscription id");

    
  }
}

1;
