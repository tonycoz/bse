package BSE::ChangePW;
use strict;
use BSE::Util::Tags qw(tag_error_img);
use BSE::Util::HTML;
use base 'BSE::UI::AdminDispatch';

our $VERSION = "1.005";

my %actions =
  (
   form=>1,
   change=>1
  );

sub actions {
  \%actions;
}

sub rights {
  +{}
}

sub default_action {
  'form';
}

sub req_form {
  my ($class, $req, $msg, $errors) = @_;

  $msg = $req->message($msg || $errors);

  my %acts;
  %acts =
    (
     $req->admin_tags(),
     message => $msg,
     ifError => 1, # all messages we display are errors
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return $req->dyn_response('admin/changepw', \%acts);
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
    unless ($user->check_password($oldpw)) {
      $req->audit
	(
	 component => "adminchangepw:changepw:badpassword",
	 msg => "User '".$user->logon."' supplied an incorrect old password when changing their password",
	 object => $user,
	 actor => $user,
	 level => "error",
	);
      $errors{oldpassword} = "Your old password is incorrect";
    }
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
  if (!$errors{newpassword}) {
    my %others = map { $_ => $user->$_() }
      BSE::TB::AdminUser->password_check_fields;
    my @errors;
    unless (BSE::TB::AdminUser->check_password_rules
	    (
	     password => $newpw,
	     username => $user->logon,
	     other => \%others,
	     errors => \@errors,
	    )) {
      $errors{newpassword} = \@errors;
    }
  }
  if (keys %errors) {
    $req->is_ajax
      and return $class->_field_error($req, \%errors);
    return $class->req_form($req, undef, \%errors);
  }

  $req->audit
    (
     component => "adminchangepw:changepw:success",
     msg => "User '".$user->logon."' successfully changed their password",
     object => $user,
     actor => $user,
     level => "notice",
    );

  $user->changepw($newpw);
  $user->save;

  $req->is_ajax
    and return $req->json_content(success => 1);

  my $r = $cgi->param('r');
  unless ($r) {
    $r = $req->url('menu', { m => "New password saved" });
  }

  return BSE::Template->get_refresh($r, $req->cfg);
}

1;
