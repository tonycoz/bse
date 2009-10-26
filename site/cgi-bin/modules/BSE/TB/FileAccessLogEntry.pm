package BSE::TB::FileAccessLogEntry;
use strict;
use base 'Squirrel::Row';
use BSE::Util::SQL qw(now_sqldatetime);

sub columns {
  return qw/id when_at siteuser_id siteuser_logon file_id owner_type owner_id category filename display_name content_type download title modwhen size_in_bytes/;
}

sub table {
  "bse_file_access_log";
}

sub defaults {
  return
    (
     when_at => now_sqldatetime(),
    );
}

1;
