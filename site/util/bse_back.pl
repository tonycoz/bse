#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::Cfg;
use BSE::TB::BackgroundTasks;

{
  chdir "$FindBin::Bin/../cgi-bin"
    or warn "Could not change to cgi-bin directory: $!\n";
  
  my $cfg = BSE::Cfg->new;

  my $cmd = shift
    or usage();

  if ($cmd eq "start") {
    do_start(\@ARGV, $cfg);
  }
  elsif ($cmd eq "status") {
    do_status(\@ARGV, $cfg);
  }
  elsif ($cmd eq "running") {
    do_running(\@ARGV, $cfg);
  }
  elsif ($cmd eq "ls" or $cmd eq "list") {
    do_list(\@ARGV, $cfg);
  }
  else {
    usage();
  }

  exit;
}

sub _get_task {
  my ($args, $cmd) = @_;

  my $task_id = shift @$args
    or usage("start missing taskid parameter");
  my $task = BSE::TB::BackgroundTasks->getByPkey($task_id)
    or usage("Unknown taskid");

  return $task;
}

sub do_start {
  my ($args, $cfg) = @_;

  my $task = _get_task($args);

  $task->check_running
    and die "Task ", $task->id, " is already running\n";

  my $msg;
  my $pid = $task->start
    (
     cfg => $cfg,
     msg => \$msg,
    );
  $pid
    or die "$msg\n";
}

sub do_status {
  my ($args, $cfg) = @_;

  my $task = _get_task($args);

  print "Task Id: ", $task->id, "\n";
  print "Description: ", $task->description, "\n";
  print "Running: ", $task->check_running ? "Yes" : "No", "\n";
  print "Last-Started: ", $task->last_started, "\n"
    if $task->last_started;
  print "Last-Completion: ", $task->last_completion, "\n"
    if $task->last_completion;
  print "Last-Exit: ", $task->last_exit, "\n"
    if $task->last_exit;
}

sub do_running {
  my ($args, $cfg) = @_;

  my $task = _get_task($args);

  exit $task->check_running ? 0 : 1;
}

sub do_list {
  my ($args, $cfg) = @_;

  for my $task (BSE::TB::BackgroundTasks->all) {
    print $task->id, "\t", 
      $task->check_running ? "Yes" : "No", "\t",
	$task->last_started || "", "\t", 
	  $task->last_completion || "", "\t",
	    $task->last_exit || "", "\t", 
	      $task->task_pid || "", "\n";
  }
}

sub usage {
  my $msg = shift;
  $msg
    and print STDERR "$msg\n";
  die <<EOS;
Usage: $0 <cmd> ...
$0 start <taskid> - start the given task
$0 status <taskid> - display status of the task
$0 running <taskid> - test if running (for shell scripts)
$0 ls
$0 list - list all configured tasks
EOS
}
