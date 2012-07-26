package BSE::Storage::LocalImages;
use strict;
use BSE::Storage::LocalBase;
our @ISA = qw(BSE::Storage::LocalBase);
use BSE::CfgInfo qw(cfg_image_uri);

our $VERSION = "1.001";

sub store {
  my ($self, $path, $basename) = @_;
  # nothing to do

  return cfg_image_uri() . '/' . $basename;
}

sub url {
  my ($self, $basename) = @_;

  return cfg_image_uri() . '/' . $basename;
}

1;
