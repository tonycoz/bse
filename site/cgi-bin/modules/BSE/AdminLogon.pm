package BSE::AdminLogon;
use strict;
use BSE::Util::Tags qw(tag_error_img);
use DevHelp::HTML;
use BSE::CfgInfo 'admin_base_url';

my %actions =
  (
   logon_form=>1,
   logon=>1,
   logoff=>1,
  );

sub dispatch {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $action;
  for my $check (keys %actions) {
    if ($cgi->param("a_$check")) {
      $action = $check;
      last;
    }
  }
  $action ||= 'logon_form';
  my $method = "req_$action";
  $class->$method($req);
}

sub req_logon_form {
  my ($class, $req, $msg, $errors) = @_;

  $errors ||= {};
  if ($msg) {
    $msg = escape_html($msg);
  }
  else {
    if (keys %$errors) {
      $msg = join("<br />", map escape_html($_), values %$errors);
    }
    else {
      $msg = '';
    }
  }

  my %acts;
  %acts =
    (
     BSE::Util::Tags->admin(undef, $req->cfg),
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return BSE::Template->get_response('admin/logon', $req->cfg, \%acts);
}

sub req_logon {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $logon = $cgi->param('logon');
  my $password = $cgi->param('password');

  my %errors;
  defined $logon && length $logon
    or $errors{logon} = "Please enter your logon name";
  defined $password && length $password
    or $errors{password} = "Please enter your password";
  %errors
    and return $class->req_logon_form($req, undef, \%errors);
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getBy(logon=>$logon);
  $user && $user->{password} eq $password
    or return $class->req_logon_form($req, "Invalid logon or password");
  $req->session->{adminuserid} = $user->{id};

  my $r = $cgi->param('r');
  unless ($r) {
    $r = admin_base_url($req->cfg) . "/cgi-bin/admin/menu.pl";
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_logoff {
  my ($class, $req) = @_;

  delete $req->session->{adminuserid};
  ++$req->session->{changed};

  my $r = admin_base_url($req->cfg) . "/cgi-bin/admin/logon.pl";

  return BSE::Template->get_refresh($r, $req->cfg);
}

1;
