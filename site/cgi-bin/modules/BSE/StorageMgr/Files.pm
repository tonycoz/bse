package BSE::StorageMgr::Files;
use strict;
use BSE::StorageMgr::Base;
our @ISA = qw(BSE::StorageMgr::Base);
use BSE::Storage::LocalFiles;
use BSE::Util::ContentType qw(content_type);

sub filebase {
  my ($self) = @_;

  my $path = $self->cfg->entryVar('paths', 'downloads');

  $path =~ m!/$! or $path .= '/';

  return $path;
}

sub local_class {
  return 'BSE::Storage::LocalFiles';
}

sub type {
  'files';
}

sub files {
  require ArticleFiles;
  return ArticleFiles->file_storages;
}

sub metadata {
  my ($self, $file) = @_;

  if ($file->{download}) {
    return
      (
       content_type => "application/octet-stream",
       content_disposition => "attachment; filename=$file->{displayName}",
      );
  }
  else {
    return
      (
       content_type => $file->{contentType},
       content_disposition => "inline; filename=$file->{displayName}",
      );
  }
}

sub set_src {
  my ($self, $file, $src) = @_;

  $file->{src} = $src;
  $file->save;
}


1;
