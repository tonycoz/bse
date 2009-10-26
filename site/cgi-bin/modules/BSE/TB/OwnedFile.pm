package BSE::TB::OwnedFile;
use strict;
use base 'Squirrel::Row';
use BSE::Util::SQL qw(now_sqldatetime);

sub columns {
  return qw/id owner_type owner_id category filename display_name content_type download title body modwhen size_in_bytes/;
}

sub table {
  "bse_owned_files";
}

sub defaults {
  return
    (
     download => 0,
     body => '',
     modwhen => now_sqldatetime(),
    );
}

1;
