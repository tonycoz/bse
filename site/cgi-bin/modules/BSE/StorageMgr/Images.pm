package BSE::StorageMgr::Images;
use strict;
use BSE::StorageMgr::Base;
our @ISA = qw(BSE::StorageMgr::Base);
use BSE::CfgInfo qw(cfg_image_dir);
use BSE::Storage::LocalImages;
use BSE::Util::ContentType qw(content_type);

sub filebase {
  my ($self) = @_;

  return cfg_image_dir($self->cfg);
}

sub local_class {
  return 'BSE::Storage::LocalImages';
}

sub type {
  'images';
}

sub files {
  require Images;
  return Images->image_storages;
}

sub metadata {
  my ($self, $image) = @_;

  return
    (
     content_type => content_type($self->{cfg}, $image->{image}) 
    );
}

sub set_src {
  my ($self, $image, $src) = @_;

  $image->{src} = $src;
  $image->save;
}

1;
