package BSE::AdminLogon;
use strict;
use BSE::Util::Tags;
use HTML::Entities;
use URI::Escape;

my %actions =
  (
   logon_form=>1,
   logon=>1,
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
  my ($class, $req, $msg) = @_;

  my %acts;
  %acts =
    (
     BSE::Util::Tags->admin(undef, $req->cfg),
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     message => $msg,
    );

  return BSE::Template->get_response('admin/logon', $req->cfg, \%acts);
}

sub req_logon {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $logon = $cgi->param('logon');
  my $password = $cgi->param('password');

  defined $logon && length $logon
    or return $class->req_logon($req, "Please enter your logon name");
  defined $password && length $password
    or return $class->req_logon($req, "Please enter your password");
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getBy(logon=>$logon);
  $user && $user->{password} eq $password
    or return $class->req_logon($req, "Invalid logon or password");
  $req->session->{adminuserid} = $user->{id};

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->cfg->entryErr('site', 'url') . "/cgi-bin/admin/menu.pl";
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}


1;
