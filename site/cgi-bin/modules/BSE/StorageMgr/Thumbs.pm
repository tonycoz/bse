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
  my $cache_dir = $self->cfg->entry('paths', 'scalecache', "$image_dir/scaled");
}

sub local_class {
  return 'BSE::Storage::LocalThumbs';
}

sub type {
  'thumbs';
}

sub files {
  my ($self) = @_;

  my $dir = $self->filebase;
  if (opendir THUMBS, $dir) {
    my @files = grep /^\w+-\.(png|gif|jpe?g)$/, readdir THUMBS;
    closedir THUMBS;

    return map 
      {
	my ($geo_id, $basefile) = split /-/, $_, 2;
	my $obj = bless 
	  {
	   geo => $geo_id,
	   basefile => $basefile,
	   image => $_,
	  }, 'BSE::StorageMgr::Thumbs::Object';
	my $store = $self->select_store($_, '', $obj);
	
	+{
	  $_,
	  $store,
	  $obj
	 }
      } @files;
  }
  else {
    return;
  }
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
