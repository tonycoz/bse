package BSE::AdminMenu;
use strict;
use BSE::Util::Tags;
use base 'BSE::UI::AdminDispatch';
use DevHelp::HTML;

our $VERSION = "1.001";

=head1 NAME

BSE::AdminMenu - implements the BSE admin menu.

=head1 SYNOPSIS

  menu.pl

=head1 DESCRIPTION

Implements the BSE admin menu and provides some other utilities.

All actions require admin access.

=head1 TARGETS

=over

=cut

my %actions =
  (
   menu=>1,
   set_state => 1,
   delete_state => 1,
   get_state => 1,
   get_matching_state => 1,
   delete_matching_state => 1,
  );

sub actions { \%actions }

sub rights { +{} }

sub default_action { 'menu' }

=item menu

Display the menu.

Template: F<admin/menu>.

Tags: standard admin tags and C<message>.

=cut

sub req_menu {
  my ($class, $req, $msg) = @_;

  my $cgi = $req->cgi;
  unless (defined $cgi->param("_t")) {
    my $def_menu = $req->cfg->entry("menu", "default");
    if ($def_menu) {
      $cgi->param("_t", $def_menu);
    }
  }

  if ($msg) {
    $msg = escape_html($msg);
  }
  else {
    $msg = $req->message;
  }

  my %acts;
  %acts =
    (
     $req->admin_tags,
     message => $msg,
    );

  return $req->dyn_response('admin/menu', \%acts);
}

=item set_state

Set a UI state value.

Parameters:

=over

=item *

name - name of the state to set

=item *

value - value to store

=back

Requires Ajax.

Returns JSON: { success: 1 }

or a field error.

=cut

sub req_set_state {
  my ($self, $req) = @_;

  $req->is_ajax
    or return $self->error($req, "Ajax requests only");
  my $cgi = $req->cgi;
  my $name = $cgi->param("name");
  my $val = $cgi->param("value");
  my %errors;
  defined $name or $errors{name} = "Missing name parameter";
  defined $val or $errors{value} = "Missing value parameter";
  keys %errors
    and return $self->_field_error($req, \%errors);

  require BSE::TB::AdminUIStates;
  my $entry = BSE::TB::AdminUIStates->user_state($req->user, $name);
  if ($entry) {
    $entry->set_val($val);
    $entry->save;
  }
  else {
    BSE::TB::AdminUIStates->make
	(
	 user_id => $req->user->id,
	 name => $name,
	 val => $val,
	);
  }

  return $req->json_content(success => 1);
}

=item get_state

Get a UI state value.

Parameters:

=over

=item *

C<name> - name of the state value to retrieve.

=back

Requires Ajax.

Returns JSON, on success:

  { "success": 1, "value": "some value" }

on failure:

  { "success": 0, "error_code": "some code" }

=cut

sub req_get_state {
  my ($self, $req) = @_;

  $req->is_ajax
    or return $self->error($req, "Ajax requests only");
  my $cgi = $req->cgi;
  my $name = $cgi->param("name");
  my %errors;
  defined $name or $errors{name} = "Missing name parameter";
  keys %errors
    and return $self->_field_error($req, \%errors);

  require BSE::TB::AdminUIStates;
  my $entry = BSE::TB::AdminUIStates->user_state($req->user, $name);

  unless ($entry) {
    return $req->json_content
      (
       success => 0,
       error_code => "NOTFOUND",
      );
  }

  return $req->json_content
    (
     success => 1,
     value => $entry->val,
    );
}

=item delete_state

Delete a UI state value.

Parameters:

=over

=item *

C<name> - name of the state value to delete.

=back

Requires Ajax.

Returns JSON, on success:

  { "success": 1 }

on failure:

  { "success": 0, "error_code": "some code" }

=cut

sub req_delete_state {
  my ($self, $req) = @_;

  $req->is_ajax
    or return $self->error($req, "Ajax requests only");
  my $cgi = $req->cgi;
  my $name = $cgi->param("name");
  my %errors;
  defined $name or $errors{name} = "Missing name parameter";
  keys %errors
    and return $self->_field_error($req, \%errors);

  require BSE::TB::AdminUIStates;
  my $entry = BSE::TB::AdminUIStates->user_state($req->user, $name);
  if ($entry) {
    $entry->remove;
  }

  return $req->json_content
    (
     success => 1,
    );
}

=item get_matching_state

Get all UI state values where the name matches a prefix.

Parameters:

=over

=item *

C<name> - prefix to match

=back

Requires Ajax.

Returns JSON, on success:

  { "success": 1, 
    "entries": [
     { "name": "some name", "value": "some value" },
     ...
     ]
   }

Matching zero states is success.

on failure:

  { "success": 0, "error_code": "some code" }

=cut

sub req_get_matching_state {
  my ($self, $req) = @_;

  $req->is_ajax
    or return $self->error($req, "Ajax requests only");
  my $cgi = $req->cgi;
  my $name = $cgi->param("name");
  my %errors;
  defined $name or $errors{name} = "Missing name parameter";
  keys %errors
    and return $self->_field_error($req, \%errors);

  require BSE::TB::AdminUIStates;
  my @entries = BSE::TB::AdminUIStates->user_matching_state($req->user, $name);

  return $req->json_content
    (
     success => 1,
     entries =>
     [ map +{ name => $_->name, value => $_->val }, @entries ],
    );
}

=item delete_matching_state

Delete all UI state values where the name matches a prefix.

Parameters:

=over

=item *

C<name> - prefix to match

=back

Requires Ajax.

Returns JSON, on success:

  { "success": 1 }

Matching zero states is success.

on failure:

  { "success": 0, "error_code": "some code" }

=cut

sub req_delete_matching_state {
  my ($self, $req) = @_;

  $req->is_ajax
    or return $self->error($req, "Ajax requests only");
  my $cgi = $req->cgi;
  my $name = $cgi->param("name");
  my %errors;
  defined $name or $errors{name} = "Missing name parameter";
  keys %errors
    and return $self->_field_error($req, \%errors);

  require BSE::TB::AdminUIStates;

  # this should really use a SQL delete statement
  my @entries = BSE::TB::AdminUIStates->user_matching_state($req->user, $name);
  for my $entry (@entries) {
    $entry->remove;
  }

  return $req->json_content
    (
     success => 1,
    );
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
