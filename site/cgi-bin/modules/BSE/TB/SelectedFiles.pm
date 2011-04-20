package BSE::TB::SelectedFiles;
use strict;
use base "Squirrel::Table";
use BSE::TB::SelectedFile;

our $VERSION = "0.001";

sub rowClass { "BSE::TB::SelectedFile" }

1;
