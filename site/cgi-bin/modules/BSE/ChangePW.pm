package BSE::ChangePW;
use strict;
use BSE::Util::Tags qw(tag_error_img);
use BSE::Permissions;
use DevHelp::HTML;

my %actions =
  (
   form=>1,
   change=>1
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
  $action ||= 'form';
  my $method = "req_$action";
  $class->$method($req);
}

sub req_form {
  my ($class, $req, $msg, $errors) = @_;

  $msg ||= $req->cgi->param('m');
  $errors ||= +{};

  if ($msg) {
    $msg = escape_html($msg);
  }
  else {
    $msg = join "<br />", map escape_html($_), values %$errors;
  }

  my %acts;
  %acts =
    (
     BSE::Util::Tags->basic(undef, $req->cgi, $req->cfg),
     BSE::Util::Tags->admin(undef, $req->cfg),
     BSE::Util::Tags->secure($req),
     message => $msg,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  my $template = 'admin/changepw';

  return BSE::Template->get_response($template, $req->cfg, \%acts);
}

sub req_change {
  my ($class, $req) = @_;

  my $cgi = $req->cgi;
  my $oldpw = $cgi->param('oldpassword');
  my $newpw = $cgi->param('newpassword');
  my $confirm = $cgi->param('confirm');

  my $user = $req->user;

  my %errors;
  if (!defined $oldpw || $oldpw eq '') {
    $errors{oldpassword} = "Enter your current password";
  }
  else {
    $oldpw eq $user->{password}
      or $errors{oldpassword} = "Your old password is incorrect";
  }
  if (!defined $newpw || $newpw eq '') {
    $errors{newpassword} = "Enter a new password";
  }
  if (!defined $confirm || $confirm eq '') {
    $errors{confirm} = "Enter the confirmation password";
  }
  if (!$errors{newpassword} && !$errors{confirm}
      && $newpw ne $confirm) {
    $errors{confirm} = "Confirmation password does not match new password";
  }
  keys %errors
    and return $class->req_form($req, undef, \%errors);

  $user->{password} = $newpw;
  $user->save;

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('menu', { m => "New password saved" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

1;
