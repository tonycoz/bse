package BSE::TB::AdminUIState;
use strict;
use base "Squirrel::Row";

our $VERSION = "1.000";

sub columns {
  qw/id user_id name val/;
}

sub table {
  "bse_admin_ui_state";
}

1;
