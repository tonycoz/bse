package BSE::TB::BackgroundTask;
use strict;
use base 'Squirrel::Row';
use BSE::Util::SQL qw(now_sqldatetime);
use Carp qw(confess);
use Errno qw(EPERM EACCES);

sub columns {
  return qw/id description modname binname bin_opts stoppable start_right running task_pid last_exit last_started last_completion long_desc/;
}

sub table {
  "bse_background_tasks";
}

sub logfilename {
  my ($self, $cfg) = @_;

  my $base_path = $cfg->entryVar("paths", "backgroundlogs");
  return $base_path . "/" . $self->id . ".log";
}

sub _find_script {
  my ($cfg, $binname) = @_;

  if ($binname =~ m!^/!) {
    -f $binname
      or return;

    return $binname;
  }

  use File::Spec;
  my @relpath;
  my $filename = join("/", @relpath, $binname);
  while (!-f $filename && @relpath < 10) {
    push @relpath, "..";
    $filename = join("/", @relpath, $binname);
  }

  -f $filename
    or return;

  return File::Spec->rel2abs($filename);
}

sub start {
  my ($self, %opts) = @_;

  my $cfg = delete $opts{cfg};
  my $msg = delete $opts{msg};
  my $foreground = delete $opts{foreground};

  # find the binary
  my $binname = $self->binname;
  my @args = split ' ', $self->bin_opts;
  if ($binname =~ s/^perl //) {
    my $script = _find_script($cfg, $binname);
    unless ($script) {
      $$msg = "Cannot find script $binname";
      return;
    }
    $binname = $^X;
    unshift @args, $script;
  }
  else {
    my $foundname = _find_script($cfg, $binname);
    unless ($foundname) {
      $$msg = "Cannot find binary $binname";
      return;
    }
    $binname = $foundname;
  }
  
  require POSIX;
  my $logfilename = $self->logfilename($cfg);
  require IO::File;
  my $outfh = IO::File->new($logfilename, "w");
  if (!$outfh && ($! == EACCES || $! == EPERM)) {
    unlink $logfilename;
    $outfh = IO::File->new($logfilename, "w");
  }

  unless ($outfh) {
    $$msg = "Cannot open logfile $logfilename: $!";
    return;
  }
  
  my $task_id = $self->id;

  unless ($foreground) {
    my $pid = fork;
    unless (defined $pid) {
      $$msg = "Could not fork: $!";
      return;
    }

    if ($pid) {
      # parent
      return $pid;
    }

    # child
    BSE::DB->forked;
  }

  # child process
  my $null = $^O eq 'MSWin32' ? "NUL" : "/dev/null";
  untie *STDIN;
  open STDIN, "<$null" 
    or die "Cannot open $null: $!";
  untie *STDOUT;
  open STDOUT, ">&".fileno($outfh)
    or die "Cannot redirect stdout: $!";
  untie *STDERR;
  open STDERR, ">&STDOUT" or die "Cannot redirect STDOUT: $!";
  unless ($foreground) {
    POSIX::setsid();
  }

  my $pid2 = fork;
  unless (defined $pid2) {
    print STDERR "Cannot start second child: $!\n";
    $self->set_running(0);
    $self->set_task_pid(undef);
    $self->save;
    if ($foreground) {
      $$msg = "Cannot start child: $!\n";
    }
    else {
      exit;
    }
  }
  
  if ($pid2) {
    # the working child pid is more interesting
    $self->set_task_pid($pid2);
    $self->set_running(1);
    $self->set_last_started(now_sqldatetime());
    $self->save;
    
    waitpid $pid2, 0;
    if ($?) {
      print STDERR "Task exited with non-zero-status: $?\n";
    }
    # this can happen hours or minutes after the original task changes
    # and it's in a different process too
    my $task = BSE::TB::BackgroundTasks->getByPkey($task_id);
    $task->set_running(0);
    $task->set_task_pid(undef);
    $task->set_last_exit($?);
    $task->set_last_completion(now_sqldatetime());
    $task->save;
    if ($foreground) {
      return $pid2;
    }
    else {
      exit;
    }
  }
  else {
    BSE::DB->forked;
    {  exec $binname, @args; } # suppress warning
      print STDERR "Exec of $binname failed: $!\n";
    exit 1;
  }
}

sub check_running {
  my ($self) = @_;

  if ($self->running) {
    if ($self->task_pid) {
      # check if it's running
      if (!kill(0, $self->task_pid)
	  && !$!{EPERM}) {
	return 0;
      }
    }
  }

  return $self->running;
}

1;
