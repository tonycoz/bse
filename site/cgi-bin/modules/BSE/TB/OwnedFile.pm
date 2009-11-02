package BSE::TB::OwnedFile;
use strict;
use base 'Squirrel::Row';
use BSE::Util::SQL qw(now_sqldatetime);
use Carp qw(confess);

sub columns {
  return qw/id owner_type owner_id category filename display_name content_type download title body modwhen size_in_bytes/;
}

sub table {
  "bse_owned_files";
}

sub defaults {
  return
    (
     download => 0,
     body => '',
     modwhen => now_sqldatetime(),
    );
}

sub download_result {
  my ($self, %opts) = @_;

  my $download = delete $opts{download} || $self->download;
  my $cfg = delete $opts{cfg} or confess "Missing cfg parameter";
  my $rmsg = delete $opts{msg} or confess "Missing msg parameter";
  my $user = delete $opts{user};

  my $filebase = $cfg->entryVar('paths', 'downloads');
  require IO::File;
  my $fh = IO::File->new("$filebase/" . $self->filename, "r");
  unless ($fh) {
    $$rmsg = "Cannot open stored file: $!";
    return;
  }

  my @headers;
  my %result =
    (
     content_fh => $fh,
     headers => \@headers,
    );
  if ($download) {
    push @headers, "Content-Disposition: attachment; filename=".$self->display_name;
    $result{type} = "application/octet-stream";
  }
  else {
    push @headers, "Content-Disposition: inline; filename=" . $self->display_name;
    $result{type} = $self->content_type;
  }
  if ($cfg->entry("download", "log_downuload", 0) && $user) {
    my $max_age = $cfg->entry("download", "log_downuload_maxage", 30);
    BSE::DB->run(bseDownloadLogAge => $max_age);
    require BSE::TB::FileAccessLog;
    BSE::TB::FileAccessLog->log_download
	(
	 user => $user,
	 file => $self,
	 download => $download,
	);
  }

  return \%result;
}

1;
