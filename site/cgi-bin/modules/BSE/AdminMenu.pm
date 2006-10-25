package BSE::AdminMenu;
use strict;
use BSE::Util::Tags;
use base 'BSE::UI::AdminDispatch';

my %actions =
  (
   menu=>1,
  );

sub actions { \%actions }

sub rights { +{} }

sub default_action { 'menu' }

sub req_menu {
  my ($class, $req, $msg) = @_;

  $msg ||= $req->cgi->param('m') || '';

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->secure($req),
     BSE::Util::Tags->admin(undef, $req->cfg),
     message => $msg,
    );

  return $req->dyn_response('admin/menu', \%acts);
}

1;
