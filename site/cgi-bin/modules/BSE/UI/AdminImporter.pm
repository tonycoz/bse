package BSE::UI::AdminImporter;
use strict;
use base 'BSE::UI::AdminDispatch';
use BSE::Importer;
use BSE::Util::Tags qw(tag_error_img);

our $VERSION = "1.000";

my %actions =
  (
   start => "bse_import",
   import => "bse_import",
  );

sub actions { \%actions }

sub rights { \%actions }

sub default_action { "start" }

=head1 NAME

BSE::UI::AdminImporter - Web UI for the import tool

=head1 DESCRIPTION

Provides a simple user interface for the import tool.

=head1 TARGETS

=over

=item start

The initial, default form for the import process.

Provides default admin tags, and the following variables:

=over

=item *

profiles - a list of hashes each with the id and label of a profile.

=item *

profile_errors - a list of errors from attempting to load profiles.

=back

Template: F<admin/import/start>.

Access required: C<bse_import>.

=cut

sub req_start {
  my ($self, $req, $errors) = @_;

  my $profiles = BSE::Importer->profiles;
  my @errors;
  my @profiles;
  my $message = $req->message($errors);
  for my $profile (keys %$profiles) {
    if (eval {
      local $SIG{__DIE__};
      BSE::Importer->new(profile => $profile, cfg => $req->cfg);
    }) {
      push @profiles, { id => $profile, label => $profiles->{$profile} };
    }
    else {
      push @errors, "Loading profile '$profile': $@";
    }
  }

  $req->set_variable(profiles => \@profiles);
  $req->set_variable(profile_errors => \@errors);
  my %acts =
    (
     $req->admin_tags,
     message => $message,
     error_img => [ \&tag_error_img, $req->cfg, $errors ],
    );

  return $req->dyn_response("admin/import/start", \%acts);
}

=item Target import

Perform import processing.

CRSF token: C<bse_admin_import>.

Template: F<admin/import/import>.

Access required: C<bse_import>.

=cut

sub req_import {
  my ($self, $req) = @_;

  $req->check_csrf("bse_admin_import")
    or return $self->req_start($req, $req->csrf_error);

  my %errors;
  my $profile = $req->cgi->param("profile");
  my $profiles = BSE::Importer->profiles;
  if (!defined $profile) {
    $errors{profile} = "No profile specified";
  }
  elsif (!$profiles->{$profile}) {
    $errors{profile} = "Unknown profile '$profile' specified";
  }

  my $file = $req->cgi->upload("file")
    or $errors{file} = "No file provided";

  keys %errors
    and return $self->req_start($req, \%errors);

  my $imp;
  {
    local $SIG{__DIE__};
    eval { $imp = BSE::Importer->new(profile => $profile, cfg => $req->cfg) }
      or return $self->req_start($req, "Cannot load profile '$profile': $@");
  }

  $req->set_variable
    (perline => sub {
       my ($cb, $templater) = @_;
       my $mycb = sub {
	 $templater->set_var(importmessage => "@_");
	 $cb->()
       };
       $imp->set_callback
	 (
	  $mycb
	 );
       local $SIG{__DIE__};
       unless (eval { $imp->process($file); 1 }) {
	 $mycb->($@);
       }
     });

  my %acts = $req->admin_tags;

  return $req->dyn_response("admin/import/import", \%acts);
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
