package BSE::UI::Background;
use strict;
use base "BSE::UI::AdminDispatch";
use BSE::TB::BackgroundTasks;
use BSE::Util::Iterate;
use BSE::Util::Tags;
use BSE::Util::SQL qw(now_sqldatetime);
use BSE::Util::HTML;
use IO::File;
use BSE::Util::Tags qw(tag_hash);
use Config;

our $VERSION = "1.000";

my %actions =
  (
   list => "",
   start => "bse_back_start",
   stop => "bse_back_stop",
   detail => "bse_back_detail",
  );

sub actions { \%actions }

sub rights { \%actions }

sub default_action { "list" }

my %signames;
if ($Config{sig_name} && $Config{sig_num}) {
  my @names = split ' ', $Config{sig_name};
  my @nums = split ' ', $Config{sig_num};
  for my $i (0 .. $#names) {
    $signames{$nums[$i]} ||= $names[$i];
  }
}

=item a_list

List all tasks.

Default action.

No parameters.

Tags:

=over

=item *

iterator begin tasks ... task foo ... iterator end tasks - tasks iterator

=item *

message - displays any passed in message

=item *

task_running - returns the result of check_running for the current
task in the tasks iterator, ie. whether the task is actually running

=item *

task_exit - the last exit code of the current task in the tasks
iterator

=item *

task_signal - the last signal number of the current task in the tasks
iterator

=back

Template: admin/back/list

=cut

sub req_list {
  my ($self, $req, $errors) = @_;

  my @all = BSE::TB::BackgroundTasks->all;
  my $it = BSE::Util::Iterate->new;
  my $message = $req->message($errors);
  my $current_task;
  my %acts =
    (
     $req->admin_tags,
     $it->make
     (
      single => "task",
      plural => "tasks",
      data => \@all,
      store => \$current_task,
     ),
     message => $message,
     task_running => [ tag_task_running => $self, \$current_task ],
     task_exit => [ tag_task_exit => $self, \$current_task ],
     task_signal => [ tag_task_signal => $self, \$current_task ],
    );

  return $req->dyn_response("admin/back/list", \%acts);
}

sub tag_task_running {
  my ($self, $rcurrent) = @_;

  $$rcurrent or return '';

  return $$rcurrent->check_running;
}

sub tag_task_exit {
  my ($self, $rcurrent) = @_;

  $$rcurrent or return '';

  return $$rcurrent->last_exit() >> 8;
}

sub tag_task_signal {
  my ($self, $rcurrent) = @_;

  $$rcurrent or return '';

  return $$rcurrent->last_exit() & 127;
}

sub _get_task {
  my ($req, $msg) = @_;

  my $id = $req->cgi->param("id");
  unless ($id) {
    $$msg = "Missing id parameter";
    return;
  }

  my $task = BSE::TB::BackgroundTasks->getByPkey($id);
  unless ($task) {
    $$msg = "Task not found";
    return;
  }

  return $task;
}

=item a_start

Start the given task.

=over

=item *

id - id of the task to start

=back

No Ajax support.

Rights required: bse_bask_start plus potentially rights specific to a
task.

=cut

sub req_start {
  my ($self, $req) = @_;

  my $msg;
  my $task = _get_task($req, \$msg)
    or return $self->req_list($req, { _ => $msg });

  $task->check_running
    and return $self->req_list($req, { _ => $task->description . " is already running" });

  my $pid = $task->start
    (
     cfg => $req->cfg,
     msg => \$msg,
    );
  if ($pid) {
    return BSE::Template->get_refresh("$ENV{SCRIPT_NAME}?m=Started+".escape_uri($task->description), $req->cfg);
  }
  else {
    return $self->req_list($req, { _ => $msg });
  }
}

=item a_detail

Display details for a given background task.

Parameters:

=over

=item *

id - id of the task to display

=back

Tags:

=over

=item *

task - the task object being displayed

=item *

task_running - result of check_running on the task, ie. test that the
task is actually running.

=item *

task_exit - exit code from the last run of the task

=item *

task_signal - signal number from the last run of the task

=item *

task_signal_name - name of the signal from the last run of the task.

=item *

log - content of the task's log file.

=back

Template: admin/back/detail

Rights required: bse_back_detail.

=cut

sub req_detail {
  my ($self, $req) = @_;

  my $msg;
  my $task = _get_task($req, \$msg)
    or return $self->req_list($req, { _ => $msg });

  my $logfilename = $task->logfilename($req->cfg);
  my $logtext = '';
  if (-f $logfilename) {
    my $fh = IO::File->new($logfilename, "r");
    if ($fh) {
      local $/;
      $logtext = <$fh>;
    }
  }
  my $signum = (($task->last_exit() || 0) & 127);
  my $signame = $signames{$signum} || '';
  my %acts =
    (
     $req->admin_tags,
     task => [ \&tag_hash, $task ],
     task_running => scalar($task->check_running),
     task_exit => scalar(($task->last_exit() || 0) >> 8),
     task_signal => $signum,
     task_signal_name => $signame,
     log => escape_html($logtext),
    );

  return $req->dyn_response("admin/back/detail", \%acts);
}

1;
