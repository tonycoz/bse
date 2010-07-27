#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_init bse_cfg);
use BSE::TB::BackgroundTasks;
use Getopt::Long;
use Time::HiRes qw(time);

my $start_time = time;
my $verbose;
GetOptions("v:i" => \$verbose);
!$verbose and defined $verbose and $verbose = 1;
$verbose ||= 0;

open MYSTDOUT, ">&STDOUT" or die "Cannot dup STDOUT: $!\n";

{
  bse_init("../cgi-bin");
  my $cfg = bse_cfg();

  my $def_nightly = "bse_session_clean";

  my @tasks = split /,/, $cfg->entry("nightly work", "jobs", $def_nightly);

  my %more_tasks = $cfg->entries("nightly work");
  delete $more_tasks{jobs};
  for my $key (sort keys %more_tasks) {
    my ($name, $extra) = split /,/, $more_tasks{$key};
    push @tasks, $name;
  }

 TASK:
  for my $task_id (@tasks) {
    my $task = BSE::TB::BackgroundTasks->getByPkey($task_id);

    unless ($task) {
      warn "Unknown task id $task_id\n";
      next TASK;
    }

    if ($task->check_running) {
      msg(1, "$task_id is already running - skipping\n");
      next TASK;
    }

    my $msg;
    msg(1, "Starting $task_id\n");
    my $pid = $task->start
      (
       cfg => $cfg,
       msg => \$msg,
       foreground => 1,
      ) or msg(0, "Could not start $task_id: $msg\n");
  }
  msg(1, "Background processing complete\n");

  exit;
}

sub msg {
  my ($level, $text) = @_;

  if ($level <= $verbose) {
    my $diff = time() - $start_time;
    printf MYSTDOUT "%.2f: %s", $diff, $text;
  }
}
