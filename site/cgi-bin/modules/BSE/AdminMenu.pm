package BSE::AdminMenu;
use strict;
use BSE::Util::Tags;
use BSE::Permissions;

my %actions =
  (
   menu=>1,
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
  $action ||= 'menu';
  my $method = "req_$action";
  $class->$method($req);
}

sub req_menu {
  my ($class, $req, $msg) = @_;

  $msg ||= $req->cgi->param('m') || '';
  BSE::Permissions->check_logon($req)
    or return BSE::Template->get_refresh($req->url('logon'), $req->cfg);

  my %acts;
  %acts =
    (
     BSE::Util::Tags->admin(undef, $req->cfg),
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     message => $msg,
    );

  my $template = 'admin/menu';
  my $t = $req->cgi->param('_t');
  $template .= "_$t" if defined($t) && $t =~ /^\w+$/;

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

1;
