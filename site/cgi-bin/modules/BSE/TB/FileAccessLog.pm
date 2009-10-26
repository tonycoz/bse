package BSE::TB::FileAccessLog;
use strict;
use base 'Squirrel::Table';
use BSE::TB::FileAccessLogEntry;
use Carp qw(confess);

sub rowClass {
  'BSE::TB::FileAccessLogEntry';
}

sub log_download {
  my ($self, %opts) = @_;

  my $user = delete $opts{user}
    or confess "No user parameter to log_download()";

  my $file = delete $opts{file}
    or confess "No file parameter to log_download()";
  
  my %args;
  for my $field (BSE::TB::FileAccessLogEntry->columns) {
    $args{$field} = $file->{$field}
      if exists $file->{$field};
  }
  delete $args{id};
  $args{file_id} = $file->id;
  $args{siteuser_id} = $user->id;
  $args{siteuser_logon} = $user->userId;
  defined $opts{download} and $args{download} = $opts{download};

  return BSE::TB::FileAccessLog->make(%args);
}

1;
