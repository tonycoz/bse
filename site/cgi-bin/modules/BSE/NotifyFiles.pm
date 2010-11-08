package BSE::NotifyFiles;
use strict;
use BSE::ComposeMail;
use BSE::DB;
use BSE::TB::OwnedFiles;
use SiteUsers;
use BSE::Util::Tags qw(tag_hash_plain);
use DevHelp::Tags::Iterate;
use BSE::TB::SiteUserGroups;
use Carp qw(confess);

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  $opts{cfg} and $opts{cfg}->can("entry")
    or confess "Missing error option\n";

  return bless \%opts, $class;
}

sub run {
  my ($self) = @_;

  $self->_lock
    or die "Cannot acquire notify_files lock\n";

  $self->_clear_obsolete;

  $self->_expand_groups;

  $self->_send_messages;

  $self->_unlock;
}

sub expand_groups {
  my ($self) = @_;

  $self->lock
    or die "Cannot acquire notify_files lock\n";

  $self->_clear_obsolete;

  $self->_expand_groups;

  $self->_unlock;
}

sub _clear_obsolete {
  my ($self) = @_;

  $self->_progress("Clearing obsolete notifcations");

  my $max_age = $self->{cfg}->entry("notify files", "oldest_notify", 7);
  BSE::DB->run(bseClearOldFileNotifications => $max_age);
}

sub _expand_groups {
  my ($self) = @_;

  $self->_progress("Expanding group notificatioons");

  # a few at a time
  while (my @group_entries = BSE::DB->query("bseNotifyFileGroupEntries")) {
    for my $group_entry (@group_entries) {
      my $file = BSE::TB::OwnedFiles->getByPkey($group_entry->{file_id});
      if ($file) {
	$self->_expand_group($group_entry, $file);
      }
      BSE::DB->run(bseDeleteFileNotification => $group_entry->{id});
    }
  }
}

sub _expand_group {
  my ($self, $entry, $file) = @_;

  if ($entry->{owner_id} > 0) {
    BSE::DB->run(bseExpandGroupFileNotification => $entry->{id});
  }
  else {
    my $group = BSE::TB::SiteUserGroups->getQueryGroup($self->{cfg}, $entry->{owner_id})
      or return;
    for my $id ($group->member_ids) {
      BSE::DB->run(bseAddOwnedFileNotificationTime => $entry->{file_id}, "U", $id, $entry->{when_at});
    }
  }
}

sub _send_messages {
  my ($self) = @_;

  $self->_progress("Sending emails");

  my @user_ids = map $_->{id}, BSE::DB->query("bseFileNotifyUsers");
  for my $user_id (@user_ids) {
    $self->_notify_user($user_id);
  }
}

sub _notify_user {
  my ($self, $user_id) = @_;

  my @orig_entries = BSE::DB->query(bseFileNotifyUserEntries => $user_id);
  if (@orig_entries) {
    my $user = SiteUsers->getByPkey($user_id);
    if ($user) {
      $self->_notify_user_low($user_id, $user, \@orig_entries);
    }
    for my $entry (@orig_entries) {
      BSE::DB->run(bseDeleteFileNotification => $entry->{id});
    }
  }
}

sub _notify_user_low {
  my ($self, $user_id, $user, $orig_entries) = @_;

  $self->_detail("Emailing: ", $user->userId);

  # we keep the original entry list, since we want to delete them all
  # at the end, but we don't want to delete entries added after we
  # started processing the user.
  my %cats = map { $_ => 1 } $user->subscribed_file_categories;
  my @unique_entries;
  my %seen;
  for my $entry (@$orig_entries) {
    $seen{$entry->{file_id}}++ and next;
    $entry->{file} = BSE::TB::OwnedFiles->getByPkey($entry->{file_id})
      or next;
    # in case the user stopped subscribing
    $cats{$entry->{file}{category}}
      or next;
    push @unique_entries, $entry;
  }
  @unique_entries
    or return;

  my @files;
  my %catnames = map { $_->{id} => $_->{name} }
    BSE::TB::OwnedFiles->categories($self->{cfg});
  for my $entry (@unique_entries) {
    my $file = $entry->{file}->data_only;
    $file->{catname} = $catnames{$file->{category}} || $file->{category};
    push @files, $file;
  }

  my $it = DevHelp::Tags::Iterate->new;
  my %acts =
    (
     BSE::Util::Tags->static(undef, $self->{cfg}),
     user => [ \&tag_hash_plain, $user ],
     $it->make
     (
      single => "file",
      plural => "files",
      data => \@files,
     ),
    );
  my $mailer = BSE::ComposeMail->new(cfg => $self->{cfg});
  $mailer->send(to => $user,
		subject => "You have files waiting",
		template => "user/notify_file",
		acts => \%acts);
}

sub _lockname {
  my ($self) = @_;

  my $cfg = $self->{cfg};
  return $cfg->entry("notify files", "lockname",
		     $cfg->entry("site", "url") . "_notify_files");
}

sub _lock {
  my ($self, $wait) = @_;

  defined $wait or $wait = 3600;
  my $dbh = BSE::DB->single->dbh;
  local $dbh->{PrintWarn} = 0;
  my $row = $dbh->selectrow_arrayref
    ("select get_lock(?, ?)", undef, $self->_lockname, $wait)
      or return;
  $row->[0]
    or return;
  return 1;
}

sub _unlock {
  my ($self) = @_;

  my $dbh = BSE::DB->single->dbh;
  $dbh->selectrow_arrayref("select release_lock(?)", undef, $self->_lockname)
    or die "Cannot release lock\n";
}

# returns true if the lock is held
sub testlock {
  my ($self) = @_;

  my $dbh = BSE::DB->single->dbh;
  my $row = $dbh->selectrow_arrayref("select is_free_lock(?)", undef, $self->_lockname)
    or die "Cannot retrieve lock status: ", $dbh->errstr, "\n";
  return !$row->[0];
}

sub _progress {
  my ($self, @text) = @_;

  $self->{verbose} && $self->{output}
    and $self->{output}->(@text);
}

sub _detail {
  my ($self, @text) = @_;

  $self->{verbose} > 1 && $self->{output}
    and $self->{output}->(@text);
}

1;
