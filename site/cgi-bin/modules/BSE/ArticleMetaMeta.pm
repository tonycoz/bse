package BSE::ArticleMetaMeta;
use strict;
use base 'BSE::MetaMeta';

our $VERSION = "1.000";

sub validation_section {
  "article metadata validation";
}

sub fields_section {
  "global article metadata";
}

sub name_section {
  my ($self, $name) = @_;

  return "article metadata $name";
}

1;
