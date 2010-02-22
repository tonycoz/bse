package BSE::TB::ArticleFileMeta;
use strict;
use base 'Squirrel::Row';

sub table {
  "bse_article_file_meta";
}

sub columns {
  qw/id file_id name content_type value appdata/;
}

sub defaults {
  content_type => "text/plain",
  appdata => 1,
}

sub is_text {
  $_[0]->content_type eq "text/plain"
}

1;
