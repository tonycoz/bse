package BSE::AdminLogon;
use strict;
use BSE::Util::Tags qw(tag_error_img);
use BSE::Util::HTML;
use BSE::CfgInfo 'admin_base_url';

our $VERSION = "1.002";

my %actions =
  (
   logon_form=>1,
   logon=>1,
   logoff=>1,
   userinfo => 1,
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
  my ($class, $req, $errors) = @_;

  my $msg = (!$errors || ref $errors) ? $req->message($errors) : escape_html($errors);

  my %acts;
  %acts =
    (
     $req->admin_tags($req),
     message => $msg,
     ifError => 1, # all messages we display are errors
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return $req->dyn_response('admin/logon', \%acts);
}

sub _service_error {
  my ($self, $req, $errors, $error_code) = @_;

  $error_code ||= "UNKNOWN";

  if ($req->cgi->param('_service')) {
    my $body = '';
    $body .= "Result: failure\n";
    if (ref $errors) {
      for my $field (keys %$errors) {
	my $text = $errors->{$field};
	$text =~ tr/\n/ /;
	$body .= "Field-Error: $field - $text\n";
      }
      my $text = join ('/', values %$errors);
      $text =~ tr/\n/ /;
      $body .= "Error: $text\n";
    }
    else {
      $body .= "Error: $errors\n";
    }
    return
      {
       type => 'text/plain',
       content => $body,
      };
  }
  elsif ($req->is_ajax) {
    return $req->json_content
      (
       {
	success => 0,
	(
	 ref $errors
	 ? ( errors => $errors )
	 : ( msg => $errors )
	),
	error_code => $error_code,
       }
      );
  }
  else {
    return $self->req_logon_form($req, $errors);
  }
}

sub _service_success {
  my ($self, $results) = @_;

  my $body = "Result: success\n";
  for my $field (keys %$results) {
    $body .= "$field: $results->{$field}\n";
  }
  return
    {
     type => 'text/plain',
     content => $body,
    };
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
    and return $class->_service_error($req, \%errors, "FIELD");
  require BSE::TB::AdminUsers;
  my $user = BSE::TB::AdminUsers->getBy(logon=>$logon);
  my $match;
  if ($user) {
    my $error;
    $match = $user->check_password($password, \$error);
    if (!$match && $error eq "LOAD") {
      $errors{logon} = "Could not load password check module for type ".$user->password_type;
      return $class->_service_error($req, \%errors, "FIELD");
    }
  }
  unless ($user && $match) {
    $req->audit
      (
       component => "adminlogon:logon:failure",
       level => "error",
       msg => "Failed logon attempt",
       actor => "U",
       object => $user,
       dump => "Logon: $logon",
      );
    return $class->_service_error($req, "Invalid logon or password", "INVALID");
  }
  $req->session->{adminuserid} = $user->{id};
  $req->audit
    (
     component => "adminlogon:logon:success",
     level => "info",
     msg => "User '" . $user->logon . "' successfully logged in",
     actor => $user,
     object => $user,
    );
  delete $req->session->{csrfp};

  if ($cgi->param('_service')) {
    return $class->_service_success({});
  }
  elsif ($req->is_ajax) {
    return $req->json_content
      (
       {
	success => 1,
	user =>
	{
	 logon => $user->logon,
	 name => $user->name || $user->logon,
	},
       }
      );
  }
  else {
    my $r = $cgi->param('r');
    unless ($r) {
      $r = admin_base_url($req->cfg) . "/cgi-bin/admin/menu.pl";
    }
    
    return BSE::Template->get_refresh($r, $req->cfg);
  }
}

sub req_logoff {
  my ($class, $req) = @_;

  $req->check_admin_logon; # populate the logon info
  my $user = $req->user;
  if ($user) {
    $req->audit
      (
       component => "adminlogon:logoff:success",
       object => $req->user,
       actor => $req->user,
       msg => "User '" . $user->logon . "' logged off",
       level => "info",
      );
    $req->flash("msg:bse/admin/logon/logoff", [ $user->logon ]);
  }

  delete $req->session->{adminuserid};
  delete $req->session->{csrfp};
  ++$req->session->{changed};

  if ($req->is_ajax) {
    return $req->json_content({ success => 1 });
  }

  my $r = admin_base_url($req->cfg) . "/cgi-bin/admin/logon.pl";

  return BSE::Template->get_refresh($r, $req->cfg);
}

sub req_userinfo {
  my ($class, $req) = @_;

  $req->is_ajax
    or return $class->req_logon_form($req, "userinfo only available from Ajax");

  my $result =
    {
     success => 1,
    };

  $req->check_admin_logon;
  my $user = $req->user;
  if ($user) {
    $result->{user} =
      {
       logon => $user->logon,
       name => $user->name || $user->logon,
      };
  }
  $result->{access_control} = $req->cfg->entry('basic', 'access_control', 0);

  return $req->json_content($result);
}

1;
