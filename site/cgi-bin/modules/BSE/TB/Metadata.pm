package BSE::TB::Metadata;
use strict;
use base 'Squirrel::Table';
use BSE::TB::MetaEntry;

our $VERSION = "1.001";

sub rowClass { "BSE::TB::MetaEntry" }

1;
