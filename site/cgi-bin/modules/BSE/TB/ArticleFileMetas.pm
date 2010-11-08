package BSE::TB::ArticleFileMetas;
use strict;
use base 'Squirrel::Table';
use BSE::TB::ArticleFileMeta;

our $VERSION = "1.000";

sub rowClass { "BSE::TB::ArticleFileMeta" }

1;
