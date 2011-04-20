package BSE::TB::SelectedFile;
use strict;
use base "Squirrel::Row";

our $VERSION = "0.001";

sub columns {
  qw/id owner_id owner_type file_id display_order/;
}

sub table {
  return "bse_selected_files";
}

1;
