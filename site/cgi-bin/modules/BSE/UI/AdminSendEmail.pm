package BSE::UI::AdminSendEmail;
use strict;
use base 'BSE::UI::AdminDispatch';
use SiteUsers;

my %actions =
  (
   send => 1,
  );

sub actions { \%actions }

sub rights {
  {}
}

sub default_action {
  "send"
}

sub req_send {
  my ($self, $req) = @_;

  # make sure the user is being authenticated in some way
  # this prevents spammers from using this to send their messages
  $ENV{REMOTE_USER} || $req->getuser
    or return $self->error($req, 
			   "You must be authenticated to use this function.  Either enable access control or setup .htpasswd.");

  my $cgi = $req->cgi;
  my $id = $cgi->param("id");
  my $user_id = $cgi->param("siteuser_id");
  $id =~ /^\w+$/
    or return $self->error($req, "Invalid email id $id");
  $req->cfg->entry("email $id", "template")
    or return $self->error($req, "Unknown email id $id - no template");

  my $secid = "bse_sendemail_$id";

  my $msg;
  $req->user_can($secid, -1, \$msg)
    or return $self->error($req, "You do not have access to send email $id");

  my $user = SiteUsers->getByPkey($user_id)
    or return $self->error($req, "Unknown user $user_id");

  my %acts =
    (
     emailuser => [ \&tag_hash_plain, $user ],
    );

  $req->send_email
    (
     to => $user,
     id => $id
    );

  my $r = $cgi->param('r');
  $r ||= '/cgi-bin/admin/menu.pl';

  return BSE::Template->get_refresh($r, $req->cfg);
}

1;

