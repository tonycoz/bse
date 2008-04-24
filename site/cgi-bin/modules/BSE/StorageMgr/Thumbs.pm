package BSE::StorageMgr::Thumbs;
use strict;
use BSE::StorageMgr::Base;
our @ISA = qw(BSE::StorageMgr::Base);
use BSE::CfgInfo qw(cfg_image_dir);
use BSE::Storage::LocalThumbs;
use BSE::Util::ContentType qw(content_type);

sub filebase {
  my ($self) = @_;

  my $image_dir = cfg_image_dir($self->cfg);
  return $self->cfg->entry('paths', 'scalecache', "$image_dir/scaled");
}

sub local_class {
  return 'BSE::Storage::LocalThumbs';
}

sub type {
  'thumbs';
}

sub _make_object {
  my ($self, $filename) = @_;

  my ($geo_id, $basefile) = split /-/, $filename, 2;

  return bless 
    {
     geo => $geo_id,
     basefile => $basefile,
     image => $filename,
    }, 'BSE::StorageMgr::Thumbs::Object';
}

sub files {
  my ($self) = @_;

  my $dir = $self->filebase;
  if (opendir THUMBS, $dir) {
    my @files = grep /^\w+-.+\.(png|gif|jpe?g)$/, readdir THUMBS;
    closedir THUMBS;

    return map 
      {
	my $obj = $self->_make_object($_);
	my $store = $self->select_store($_, '', $obj);
	
	[
	 $_,
	 $store,
	 $obj
	]
      } @files;
  }
  else {
    return;
  }
}

sub store {
  my ($self, $filename, $key, $object) = @_;

  defined $key or $key = '';
  $object ||= $self->_make_object($filename);
  $key = $self->select_store($filename, $key, $object);

  return $self->SUPER::store($filename, $key, $object);
}

sub url {
  my ($self, $filename, $key, $object) = @_;

  defined $key or $key = '';
  $object ||= $self->_make_object($filename);
  $key = $self->select_store($filename, $key, $object);

  return $self->SUPER::url($filename, $key, $object);
}

sub metadata {
  my ($self, $image) = @_;

  return
    (
     content_type => content_type($self->{cfg}, $image->{image}) 
    );
}

sub set_src {
  my ($self, $obj, $src) = @_;

  $obj->{src} = $src;
}

package BSE::StorageMgr::Thumbs::Object;

1;
