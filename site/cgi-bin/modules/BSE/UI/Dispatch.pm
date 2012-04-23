package BSE::UI::Dispatch;
use strict;
use Carp 'confess';

our $VERSION = "1.004";

sub new {
  my ($class, %opts) = @_;

  bless \%opts, $class;
}

sub dispatch {
  my ($self, $req) = @_;

  my $result;
  $self->check_secure($req, \$result)
    or return $result;

  my $actions = $self->actions;

  my $prefix = $self->action_prefix;
  my $cgi = $req->cgi;
  my $action;
  if (ref $self) {
    $action = $self->action;
    defined $action && $actions->{$action} 
      or undef $action;
  }
  unless ($action) {
    for my $check (keys %$actions) {
      if ($cgi->param("a_$check") || $cgi->param("a_$check.x")) {
	$action = $check;
	last;
      }
    }
    if (!$action && $prefix ne 'a_') {
      for my $check (keys %$actions) {
	if ($cgi->param("$prefix$check") || $cgi->param("$prefix$check.x")) {
	  $action = $check;
	  last;
	}
      }
    }
  }
  my @extras;
  my $rest = '';
  unless ($action) {
    ($action, @extras) = $self->other_action($cgi);
  }
  if (!$action && $ENV{PATH_INFO}) {
    my @components = split '/', $ENV{PATH_INFO};
    @components && !$components[0] and shift @components;
    if (@components && $actions->{$components[0]}) {
      $action = $components[0];
      $rest = join '/', @components[1..$#components]
	if @components > 1;
    }
  }
  $action ||= $self->default_action;

  $self->check_action($req, $action, \$result)
    or return $result;

  ref $self and $self->{action} = $action;
  ref $self and $self->{rest} = $rest;
  $req->set_variable(action => $action);

  my $method = "req_$action";
  $self->$method($req, @extras);
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

# returns a result of an error page
sub error {
  my ($class, $req, $errors, $template) = @_;

  unless (ref $errors) {
    $errors = { error => $errors };
  }

  my $msg = $req->message($errors);

  $template ||= 'error';

  require BSE::Util::Tags;
  my %acts;
  %acts =
    (
     $req->dyn_user_tags(),
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
     msg => $msg,
     error => $msg, # so we can use the original error.tmpl
    );

  return $req->response($template, \%acts);
}

sub _field_error {
  my ($self, $req, $errors) = @_;

  return $req->field_error($errors);
}

sub controller_id {
  $_[0]{controller_id};
}

sub action {
  $_[0]{action};
}

sub rest {
  $_[0]{rest};
}

1;
