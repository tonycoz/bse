package BSE::UI::AdminIPAddress;
use strict;
use base "BSE::UI::AdminDispatch";
use BSE::TB::IPLockouts;
use Net::IP;
use BSE::Util::SQL qw(now_datetime);

our $VERSION = "1.000";

my %actions =
  (
   list => "bse_ipaddress_list",
   detail => "bse_ipaddress_detail",
   unlock => "bse_ipaddress_unlock",
  );

sub actions { \%actions }

sub default_action { "list" }

sub rights { \%actions }

sub req_list {
  my ($self, $req, $errors) = @_;

  my %ips;
  for my $lockout (BSE::TB::IPLockouts->getBy2
		   (
		    [
		     [ '>', expires => now_datetime() ],
		    ]
		   )) {
    $ips{$lockout->ip_address}{"lockout_" . $lockout->type} =  $lockout->expires;
  }
  my @ips =
    map $_->[0],
    sort { $a->[1]->hexip cmp $b->[1]->hexip }
      map [ $_, Net::IP->new($_->{ip_address}) ],
	map
	  {
	    my $ip = $ips{$_};
	    $ip->{ip_address} = $_;
	    $ip;
	  } keys %ips;

  $req->set_variable(ips => \@ips);
  my $mesage = $req->message($errors);

  my %acts =
    (
     $req->admin_tags,
    );

  return $req->dyn_response("admin/ip/list", \%acts);
}

sub _ip_check {
  my ($ip) = @_;

  # currently this only acceps IPv4 addresses and should be updated
  # later

  $ip =~ /\A(?:[0-9]+\.){3}[0-9]+\z/
    or return;

  my @nums = split /\./, $ip;
  @nums == 4
    or return;
  grep $_ > 255, @nums
    and return;

  return 1;
}

sub req_detail {
  my ($self, $req, $errors) = @_;

  my $ip = $req->cgi->param("ip");
  $ip
    or return $self->req_list($req, { ip => "Missing ip parameter" });

  _ip_check($ip)
    or return $self->req_list($req, { ip => "Invalid ip parameter" });

  my %ip = ( ip_address => $ip );
  for my $entry (BSE::TB::IPLockouts->getBy2
    (
     [
      [ '>', expires => now_datetime() ],
      [ ip_address => $ip ],
     ]
    )) {
    $ip{"lockout_".$entry->type} = $entry->expires;
  }

  $req->set_variable(ip => \%ip);
  my $mesage = $req->message($errors);

  my %acts =
    (
     $req->admin_tags,
    );

  return $req->dyn_response("admin/ip/detail", \%acts);
}

sub req_unlock {
  my ($self, $req) = @_;

  my $cgi = $req->cgi;
  my $ip = $cgi->param("ip");
  $ip
    or return $self->req_list($req, { ip => "Missing ip parameter" });

  _ip_check($ip)
    or return $self->req_list($req, { ip => "Invalid ip parameter" });

  my $type = $cgi->param("type");

  my ($entry) = BSE::TB::IPLockouts->getBy
    (
     ip_address => $ip,
     type => $type,
    );

  if ($entry) {
    if ($type eq "S") {
      require SiteUsers;
      SiteUser->unlock_ip_address
	(
	 ip_address => $ip,
	 request => $req,
	);
      $entry->remove;
      $req->flash_notice("msg:bse/admin/ipaddress/siteunlock", [ $ip ]);
    }
    elsif ($type eq "A") {
      require BSE::TB::AdminUsers;
      BSE::TB::AdminUser->unlock_ip_address
	  (
	   ip_address => $ip,
	   request => $req,
	  );
      $entry->remove;
      $req->flash_notice("msg:bse/admin/ipaddress/adminunlock", [ $ip ]);
    }
    else {
      $req->flash_notice("Unknown lock type '$type'");
    }
  }
  else {
    $req->flash_notice("No lock to remove");
  }

  my $url = $cgi->param("r") || $req->cfg->admin_url2("ipaddress", "list");
  return $req->get_refresh($url);
}

1;
