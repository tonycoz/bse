package BSE::TB::MetaEntry;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.001";

sub table {
  "bse_article_file_meta";
}

sub columns {
  qw/id file_id name content_type value appdata owner_type/;
}

sub defaults {
  content_type => "text/plain",
  appdata => 1,
}

sub is_text {
  $_[0]->content_type eq "text/plain"
}

1;
