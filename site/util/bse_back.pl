#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::Cfg;
use BSE::TB::BackgroundTasks;
use Getopt::Long;

{
  chdir "$FindBin::Bin/../cgi-bin"
    or warn "Could not change to cgi-bin directory: $!\n";
  
  my $cfg = BSE::Cfg->new;

  my $cmd = shift
    or usage();

  if ($cmd eq "start") {
    do_start(\@ARGV, $cfg, $cmd, 0);
  }
  elsif ($cmd eq "run") {
    do_start(\@ARGV, $cfg, $cmd, 1);
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
    or usage("$cmd: missing taskid parameter");
  my $task = BSE::TB::BackgroundTasks->getByPkey($task_id)
    or usage("$cmd: Unknown taskid '$task_id'");

  return $task;
}

sub do_start {
  my ($args, $cfg, $cmd, $foreground) = @_;

  my $task = _get_task($args, $cmd);

  $task->check_running
    and die "Task ", $task->id, " is already running\n";

  my $msg;
  my $pid = $task->start
    (
     cfg => $cfg,
     msg => \$msg,
     foreground => $foreground,
    );
  $pid
    or die "$msg\n";
}

sub do_status {
  my ($args, $cfg) = @_;

  my $task = _get_task($args, "status");

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

  my $task = _get_task($args, "running");

  exit $task->check_running ? 0 : 1;
}

sub do_list {
  my ($args, $cfg) = @_;

  my $fields = "id,running,started,completed,exit,signal,pid";
  my $raw;

  GetOptions("f=s", \$fields,
	     "r" => \$raw);

  my @rows;

  my @tasks;
  my @matches;
  if (@$args) {
    for my $arg (@$args) {
      my $work = $arg;
      $work =~ s/\./\\./g;
      $work =~ s/\*/.*/g;
      $work =~ s/\?/.?/g;
      push @matches, qr/^$work$/;
    }

  TASK:
    for my $task (BSE::TB::BackgroundTasks->all) {
      for my $match (@matches) {
	if ($task->id =~ $match) {
	  push @tasks, $task;
	  next TASK;
	}
      }
    }
  }
  else {
    @tasks = BSE::TB::BackgroundTasks->all;
  }

  for my $task (@tasks) {
    my $wait = $task->last_exit || 0;
    push @rows,
      {
       id => $task->id,
       running => $task->check_running ? "Yes" : "No",
       started => $task->last_started || "",
       completed => $task->last_completion || "",
       exit => ($wait >> 8),
       signal => ($wait & 0x7f),
       pid => $task->task_pid || "",
      };
  }

  my @fields = split /,/, $fields;

  if ($raw) {
    for my $row (@rows) {
      print join("\t", @{$row}{@fields}), "\n";
    }
  }
  else {
    # calculate column widths
    my %widths = map { $_ => 1 } @fields;
    for my $row ({ map { $_ => $_ } @fields }, @rows) {
      for my $field (@fields) {
	if (length $row->{$field} > $widths{$field}) {
	  $widths{$field} = length $row->{$field};
	}
      }
    }

    for my $field (@fields) {
      printf "%-*s|", $widths{$field}, $field;
    }
    print "\n";
    for my $row (@rows) {
      for my $field (@fields) {
	printf "%-*s|", $widths{$field}, $row->{$field};
      }
      print "\n";
    }
  }
}

sub usage {
  my $msg = shift;
  $msg
    and print STDERR "$msg\n";
  die <<EOS;
Usage: $0 <cmd> ...
$0 start <taskid> - start the given task
$0 run <taskid> - run in foreground
$0 status <taskid> - display status of the task
$0 running <taskid> - test if running (for shell scripts)
$0 ls
$0 list - list all configured tasks
EOS
}
