package BSE::UI::Dispatch;
use strict;
use Carp 'confess';

our $VERSION = "1.005";

=head1 NAME

BSE::UI::Dispatch - user interface dispatch code

=head1 DESCRIPTION

This class provides simple method dispatch for CGI/FastCGI user
interfaces for BSE.

An implementation must provide the methods:

=over

=item actions()

Returns a hash of which the keys represent valid action names.

=item default_action()

returns the name of the default action, used if no parameter or
C<PATH_INFO> can be found that matches an entry in the result of
actions().

=back

=head1 METHODS

=over

=item new()

Create a new dispatch object.

=cut

sub new {
  my ($class, %opts) = @_;

  bless \%opts, $class;
}

=item dispatch($req)

Dispatch a request.

Once an action is found this will call method C<< req_I<action-name>
>> to perform any processing.

Any extra path parameters can be retrieved using the rest() method.

=cut

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

  my $csrfp = $self->csrfp_tokens;
  if ($csrfp && $csrfp->{$action}) {
    my $entry = $csrfp->{$action};
    $entry = ref $entry ? $entry : { token => $entry };
    my $token = $entry->{token};
    unless ($req->check_csrf($entry->{token})) {
      $action = $entry->{target} || $self->default_action;
      @extras = ();
      $req->flash_error($req->csrf_error);
    }
  }

  ref $self and $self->{action} = $action;
  ref $self and $self->{rest} = $rest;
  $req->set_variable(action => $action);

  my $method = "req_$action";
  $self->$method($req, @extras);
}

=item check_secure($req, \$result)

Override this to perform security checks, as done by
L<BSE::UI::AdminRequest> to ensure SSL is used when needed.

=cut

sub check_secure {
  my ($class, $req, $rresult) = @_;

  return 1;
}

=item check_action($req, $action \$result)

Used to check any extra requirements for a particular action.

L<BSE::UI::AdminDispatch> uses this to ensure the user has the rights
necessary to perform an action.

=cut

sub check_action {
  my ($class, $req, $action, $rresult) = @_;

  return 1;
}

=item other_action($cgi)

Override to provide fallback action checking.

If dispatch() can't find an action itself, it will call other_action()
to determine the action.

=cut

sub other_action {
  return;
}

=item action_prefix

Returns the prefix expected on CGI parameters for action names.

This is intended for backward compatibility and shouldn't be used in
new code.

=cut

sub action_prefix {
  'a_';
}

=item error($req, $errors, $template)

Return an error page.

If not supplied, $template defaults to C<"error">.

=cut

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

=item csrfp_tokens

Override to provide csrfp tokens that should be present by action.

The return valid is a hash ref, where the keys are actions and the
values are either the required token, or a hash reference containing:

=over

=item *

C<token> - the required token

=item *

C<target> - the alternative target to dispatch instead.

=back

=cut

sub csrfp_tokens {
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
