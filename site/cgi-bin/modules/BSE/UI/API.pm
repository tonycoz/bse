package BSE::UI::API;
use strict;
use base "BSE::UI::Dispatch";

our $VERSION = "1.001";

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
  my %result =
    (
     success => 1,
     perlbal => $cfg->entry("basic", "perlbal", 0),
     access_control => $cfg->entry("basic", "access_control", 0),
     tracking_uploads => $req->_tracking_uploads,
    );

  my %custom = $cfg->entries("extra a_config");
  for my $key (keys %custom) {
    exists $result{$key} and next;

    my $section = $custom{$key};
    $section =~ /\{(level|generator|parentid|template)\}/
      and next;

    $section eq "db" and die;

    $result{$key} = { $cfg->entries($section) };
  }

  return $req->json_content(\%result);
}

sub req_fail {
  my ($self, $req) = @_;

  return $self->error($req, "Not for end-user use");
}

1;
