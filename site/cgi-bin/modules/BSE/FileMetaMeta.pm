package BSE::FileMetaMeta;
use strict;
use base 'BSE::MetaMeta';

our $VERSION = "1.002";

sub validation_section {
  "file metadata validation";
}

sub fields_section {
  "global file metadata";
}

sub name_section {
  my ($self, $name) = @_;

  return "file metadata $name";
}

1;
