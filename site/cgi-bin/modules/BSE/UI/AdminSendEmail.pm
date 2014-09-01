package BSE::UI::AdminSendEmail;
use strict;
use base 'BSE::UI::AdminDispatch';
use BSE::TB::SiteUsers;
use BSE::Util::Tags qw(tag_hash_plain);

our $VERSION = "1.002";

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

sub tag_ifUserCanSee {
  my ($req, $user, $args) = @_;

  $args 
    or return 0;

  my $article;
  if ($args =~ /^\d+$/) {
    require BSE::TB::Articles;
    $article = BSE::TB::Articles->getByPkey($args);
  }
  else {
    $article = $req->get_article($args);
  }
  $article
    or return 0;

  $req->siteuser_has_access($article, $user);
}

sub tag_ifUserMemberOf {
  my ($req, $user, $args, $acts, $func, $templater) = @_;

  require DevHelp::Tags;
  my ($name) = DevHelp::Tags->get_parms($args, $acts, $templater);

  $name
    or return 0; # no group name
  
  require BSE::TB::SiteUserGroups;
  my $group = BSE::TB::SiteUserGroups->getByName($req->cfg, $name);
  unless ($group) {
    print STDERR "Unknown group name '$name' in ifUserMemberOf\n";
    return 0;
  }

  return $group->contains_user($user);
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

  my $user = BSE::TB::SiteUsers->getByPkey($user_id)
    or return $self->error($req, "Unknown user $user_id");

  my %acts =
    (
     user => [ \&tag_hash_plain, $user ],
     ifUser => 1,
     ifUserCanSee => [ \&tag_isUserCanSee, $req, $user ],
     ifUserMemberOf => [ \tag_ifUserMemberOf => $req, $user ],
    );

  $req->send_email
    (
     to => $user,
     id => $id,
     extraacts => \%acts,
    );

  my $r = $cgi->param('r');
  $r ||= '/cgi-bin/admin/menu.pl';

  return BSE::Template->get_refresh($r, $req->cfg);
}

1;

