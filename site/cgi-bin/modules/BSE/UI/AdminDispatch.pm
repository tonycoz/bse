package BSE::UI::AdminDispatch;
use strict;
use base qw(BSE::UI::Dispatch);
use BSE::CfgInfo qw(admin_base_url);
use Carp qw(confess);

# checks we're coming from HTTPS
sub check_secure {
  my ($class, $req, $rresult) = @_;

  my $securl = admin_base_url($req->cfg);
  my ($protocol, $host) = $securl =~ m!^(\w+)://([-\w.]+)!
    or confess "Invalid [site].secureurl\n";
  
  $host = lc $host;

  my $curr_host = lc $ENV{SERVER_NAME};
  my $curr_https = exists $ENV{HTTPS} || exists $ENV{SSL_CIPHER};
  my $curr_proto = $curr_https ? 'https' : 'http';

  return 1 if $curr_host eq $host && $curr_proto eq $protocol;

  print STDERR "User is coming to use via a non-secure URL\n";
  print STDERR "curr host  >$curr_host< secure_host >$host<\n";
  print STDERR "curr proto >$curr_proto< secure_proto >$protocol<\n";

  # refresh back to the secure URL
  my $target = ($ENV{SCRIPT_NAME} =~ /(\w+)\.pl$/)[0] or die;
  my $url = $req->url($target => { $class->default_action => 1 });
  $$rresult = BSE::Template->get_refresh($url, $req->cfg);

  return;
}

sub check_action {
  my ($class, $req, $action, $rresult) = @_;

  # this is admin, the user must be logged on
  unless ($req->check_admin_logon) {
    # time to logon
    # if this was a GET, try to refresh back to it after logon
    my %extras =
      (
       'm' => 'You must logon to use this function'
      );
    if ($ENV{REQUEST_METHOD} eq 'GET') {
      my $rurl = admin_base_url($req->cfg) . $ENV{SCRIPT_NAME};
      $rurl .= "?" . $ENV{QUERY_STRING} if $ENV{QUERY_STRING};
      $rurl .= $rurl =~ /\?/ ? '&' : '?';
      $rurl .= "refreshed=1";
      $extras{r} = $rurl;
    }
    my $url = $req->url(logon => \%extras);
    $$rresult = BSE::Template->get_refresh($url, $req->cfg);
    return;
  }

  my $security = $class->rights;

  return 1 unless $security->{$action};

  my $msg;
  my $rights = $security->{$action};
  ref $rights or $rights = [ split /,/, $rights ];
  for my $right (@$rights) {
    unless ($req->user_can($right, -1, \$msg)) {
      my $url = $req->url(menu => 
			  { 'm' => 'You do not have access to this function '.$msg });
      $$rresult = BSE::Template->get_refresh($url, $req->cfg);
      return;
    }
  }

  return 1;
}

1;
