package BSE::UI::Dispatch;
use strict;
use Carp 'confess';

sub dispatch {
  my ($class, $req) = @_;

  my $result;
  $class->check_secure($req, \$result)
    or return $result;

  my $actions = $class->actions;

  my $cgi = $req->cgi;
  my $action;
  for my $check (keys %$actions) {
    if ($cgi->param("a_$check")) {
      $action = $check;
      last;
    }
  }
  $action ||= $class->default_action;

  $class->check_action($req, $action, \$result)
    or return $result;

  my $method = "req_$action";
  $class->$method($req);
}

sub check_secure {
  my ($class, $req, $rresult) = @_;

  return 1;
}

sub check_action {
  my ($class, $req, $action, $rresult) = @_;

  return 1;
}

1;
