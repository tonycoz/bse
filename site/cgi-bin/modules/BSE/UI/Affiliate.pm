package BSE::UI::Affiliate;
use strict;
use base qw(BSE::UI::Dispatch BSE::UI::SiteuserCommon);
use BSE::Util::Tags qw(tag_hash);
use DevHelp::HTML;

my %actions =
  (
   set => 1,
   set2 => 1,
   show => 1,
   none => 1,
  );

sub actions { \%actions }

sub default_action { 'show' }

=head1 NAME

BSE::UI::Affiliate - set the affiliate code for new orders or display a user info page

=head1 SYNOPSIS

# display a user's information or affiliate page

http://your.site.com/cgi-bin/affiliate.pl?id=I<number>

http://your.site.com/cgi-bin/affiliate.pl?lo=I<logon>

http://your.site.com/cgi-bin/affiliate.pl?co=I<affiliate name>

# set the stored affiliate code and refresh to the top of the site

http://your.site.com/cgi-bin/affiliate.pl?a_set=1&id=I<code>

# set the stored affiliate code and refresh to I<url>

http://your.site.com/cgi-bin/affiliate.pl?a_set=1&id=I<code>&r=I<url>

=head1 DESCRIPTION

This is the implementation of L<affiliate.pl>.

=head1 TARGETS

=over

=item a_set

This is called to set the affiliate code.

Requires that an C<id> parameter be supplied with the affiliate code
which is stored in the user session.  This is then stored in the order
record if the user creates an order before the cookie expires.  This
id can be any string, it need not be a user on the current site.

Optionally, you can supply a C<r> parameter which will be refreshed to
after the affiliate code is set.  If this is not supplied there will
be a refresh to either C<default_refresh> in C<[affiliate]> in
C<bse.cfg> or to the top of the site.

If your site url and site secureurl are different then there will be
an intermediate refresh to C<a_set2> to set the affiliate code on the
other side of the site.  C<a_set2> will then refresh to your supplied
C<r> parameter or its default.

You can also configure which referer header values are permitted in
bse.cfg.  See L<config/[affiliate]> for more information.

=cut

sub req_set {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $id = $cgi->param('id');

  defined($id) && $id =~ /^\w+$/
    or return $class->req_none($req, "Missing or invalid id");

  my $allowed_referer = $cfg->entry('affiliate', 'allowed_referer');
  my $require_referer = $cfg->entry('affiliate', 'require_referer');
  if ($allowed_referer) {
    my @allowed = split /;/, $allowed_referer;
    my $referer = $ENV{HTTP_REFERER};
    if ($referer) {
      my ($domain) = ($referer =~ m!^\w+://([\w.]+)!);
      $domain = lc $domain;
      my $found = 0;
      for my $entry (@allowed) {
	$entry = lc $entry;

	if (length($entry) <= length($domain) &&
	    $entry eq substr($domain, -length($entry))) {
	  ++$found;
	  last;
	}
      }
      $found
	or return $class->req_none($req, "$referer not in the permitted list of referers");
    }
    else {
      $require_referer
	and return $class->req_none($req, 'Referer not supplied');
    }
  }

  my $url = $cgi->param('r');
  $url ||= $cfg->entry('affiliate', 'default_refresh');
  $url ||= $cfg->entryVar('site', 'url');

  $req->session->{affiliate_code} = $id;

  # set it on the other side too, if needed
  my $baseurl = $cfg->entryVar('site', 'url');
  my $securl = $cfg->entryVar('site', 'secureurl');
  
  if ($baseurl eq $securl) {
    return BSE::Template->get_refresh($url, $cfg);
  }
  else {
    # which host are we on?
    # first get info about the 2 possible hosts
    my ($baseprot, $basehost, $baseport) = 
      $baseurl =~ m!^(\w+)://([\w.-]+)(?::(\d+))?!;
    $baseport ||= $baseprot eq 'http' ? 80 : 443;

    # get info about the current host
    my $port = $ENV{SERVER_PORT} || 80;
    my $ishttps = exists $ENV{HTTPS} || exists $ENV{SSL_CIPHER};
    my $protocol = $ishttps ? 'https' : 'http';

    my $onbase = 1;
    if (lc $ENV{SERVER_NAME} ne lc $basehost
       || lc $protocol ne $baseprot
       || $baseport != $port) {
      print STDERR "not on base host ('$ENV{SERVER_NAME}' cmp '$basehost' '$protocol cmp '$baseprot'  $baseport cmp $port\n";
      $onbase = 0;
    }

    my $setter = $onbase ? $securl : $baseurl;
    $setter .= "$ENV{SCRIPT_NAME}?a_set2=1&id=".escape_uri($id);
    $setter .= "&r=".escape_uri($url);
    return BSE::Template->get_refresh($setter, $cfg);
  }
}

=item a_set2

Sets the affiliate code for the "other" side of the site.

This should only be linked to by the C<a_set> target.

This does no referer checks.

=cut

# yes, this completely removes any point of the referer checks, but
# since referer checks aren't a security issue anyway, it doesn't
# matter 

sub req_set2 {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;
  my $id = $cgi->param('id');

  defined($id) && $id =~ /^\w+$/
    or return $class->req_none($req, "Missing or invalid id");

  $req->session->{affiliate_code} = $id;

  my $url = $cgi->param('r');
  $url ||= $cfg->entry('affiliate', 'default_refresh');
  $url ||= $cfg->entryVar('site', 'url');

  return BSE::Template->get_refresh($url, $cfg);
}

=item a_show

Display the affiliate page based on a either a user id number supplied
in the C<id> paramater, a logon name supplied in the C<lo> parameter
or an affiliate name supplied in the C<co> parameter.

This is the default target, so you do not need to supply a target
parameter.

The page is displayed based on the C<affiliate.tmpl> template.

The basic user side tags are available, as well as the C<siteuser> tag
which gives access to the site user's record.

Be careful about which information you display.

=cut

sub req_show {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $cfg = $req->cfg;

  require SiteUsers;
  my $user;
  my $id = $cgi->param('id');
  my $lo = $cgi->param('lo');
  my $co = $cgi->param('co');
  if (defined $id && length $id && $id =~ /^\d+$/) {
    $user = SiteUsers->getByPkey($id);
  }
  elsif (defined $lo && length $lo && $lo =~ /^\w+$/) {
    $user = SiteUsers->getBy(userId => $lo);
  }
  elsif (defined $co && length $co && $co =~ /^\w+$/) {
    $user = SiteUsers->getBy(affiliate_name => $co);
  }
  else {
    return $class->req_none($req, "No identifier supplied");
  }
  $user
    or return $class->req_none($req, "Unknown user");
  $user->{disabled}
    and return $class->req_none($req, "User disabled");
  require BSE::TB::Subscriptions;
  my $subid = $cfg->entry('affiliate', 'subscription_required');
  if ($subid) {
    my $sub = BSE::TB::Subscriptions->getByPkey($subid)
      || BSE::TB::Subscriptions->getBy(text_id => $subid)
 	or return $class->req_none($req, "Configuration error: Unknown subscription id");
    unless ($user->subscribed_to($sub)) {
      return $class->req_none($req, "User not subscribed to the required subscription");
    }
  }
  my $flag = $cfg->entry('affiliate', 'flag_required');
  if (defined $flag) {
    $user->{flags} =~ /\Q$flag/
      or return $class->req_none($req, "User not flagged with the affiliate flag $flag");
  }

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     $class->_display_tags($user, $req->cfg),
    );

  return $req->dyn_response('affiliate', \%acts);
}

sub req_none {
  my ($class, $req, $msg) = @_;

  print STDERR "Something went wrong: $msg\n" if $msg;

  # just refresh to the home page
  my $url = $req->cfg->entry('site', 'url');
  return BSE::Template->get_refresh($url, $req->cfg);
}

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut


1;
