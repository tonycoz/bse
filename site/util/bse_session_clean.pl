#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_init bse_cfg);
use BSE::DB;
use Getopt::Long;
use Time::HiRes qw(time);

my $start_time = time;
my $verbose;
GetOptions("v:i" => \$verbose);
!$verbose and defined $verbose and $verbose = 1;
$verbose ||= 0;

{
  bse_init("../cgi-bin");
  my $cfg = bse_cfg();

  my $dbh = BSE::DB->single->dbh;

  my $day_limit = $cfg->entry("session cleanup", "days", 30);
  my $per_limit = $cfg->entry("session cleanup", "per", 1000);
  my $count_limit = $cfg->entry("session cleanup", "count", 1000);
  my $optimize = $cfg->entry("session cleanup", "optimize", 1);
  msg(3, "Limits: $day_limit days, $per_limit records per request, $count_limit requests\n");

  my $sql = <<'SQL';
delete low_priority from sessions
where whenChanged < date_sub(now(), interval ? day)
limit ?
SQL

  my $sth = $dbh->prepare($sql)
    or die "Cannot prepare sql: ", $dbh->errstr, "\n";

  my $i = 0;
  my $removed = 0;
  while ($i++ < $count_limit) {
    my $thistime = $sth->execute($day_limit, $per_limit)
      or die "Could not execute delete sql: ", $dbh->errstr, "\n";
    $thistime += 0; # clean up "0E0"
    msg(2, "Loop $i/$count_limit: removed $thistime records\n");
    $removed += $thistime;
    $thistime > 0 or last;
  }
  msg(1, "Removed $removed records\n");
  if ($optimize) {
    msg(2, "Optimizing table\n");
    $dbh->do("optimize table sessions")
      or die "Cannot optimize table: ", $dbh->errstr, "\n";
  }
  msg(1, "Finished\n");

  exit;
}

sub msg {
  my ($level, $text) = @_;

  if ($level <= $verbose) {
    my $diff = time() - $start_time;
    printf("%.2f: %s", $diff, $text);
  }
}
