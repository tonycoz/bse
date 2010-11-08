package BSE::UI::API;
use strict;
use base "BSE::UI::Dispatch";

our $VERSION = "1.000";

my %actions =
  (
   config => 1,
   fail => 1,
  );

sub actions {
  \%actions;
}

sub default_action {
  "fail"
}

sub req_config {
  my ($self, $req) = @_;

  my $cfg = $req->cfg;
  return $req->json_content
    (
     success => 1,
     perlbal => $cfg->entry("basic", "perlbal", 0),
     access_control => $cfg->entry("basic", "access_control", 0),
     tracking_uploads => $req->_tracking_uploads,
    );
}

sub req_fail {
  my ($self, $req) = @_;

  return $self->error($req, "Not for end-user use");
}

1;
