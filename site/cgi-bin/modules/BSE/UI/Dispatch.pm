package BSE::UI::Dispatch;
use strict;
use Carp 'confess';

sub dispatch {
  my ($class, $req) = @_;

  my $result;
  $class->check_secure($req, \$result)
    or return $result;

  my $actions = $class->actions;

  my $prefix = $class->action_prefix;
  my $cgi = $req->cgi;
  my $action;
  for my $check (keys %$actions) {
    if ($cgi->param("$prefix$check") || $cgi->param("$prefix$check.x")) {
      $action = $check;
      last;
    }
  }
  if (!$action && $prefix ne 'a_') {
    for my $check (keys %$actions) {
      if ($cgi->param("a_$check") || $cgi->param("a_$check.x")) {
	$action = $check;
      last;
      }
    }
  }
  my @extras;
  unless ($action) {
    ($action, @extras) = $class->other_action($cgi);
  }
  $action ||= $class->default_action;

  $class->check_action($req, $action, \$result)
    or return $result;

  my $method = "req_$action";
  $class->$method($req, @extras);
}

sub check_secure {
  my ($class, $req, $rresult) = @_;

  return 1;
}

sub check_action {
  my ($class, $req, $action, $rresult) = @_;

  return 1;
}

sub other_action {
  return;
}

sub action_prefix {
  'a_';
}

1;
