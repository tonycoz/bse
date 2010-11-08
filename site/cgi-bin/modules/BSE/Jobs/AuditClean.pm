package BSE::Jobs::AuditClean;
use strict;
use BSE::DB;

our $VERSION = "1.000";

sub run {
  my $days = BSE::Cfg->single->entry("basic", "audit_log_age", 30);
  my $count = BSE::DB->run(bseAuditLogClean => $days);
  print "$count records removed\n";
}

1;
