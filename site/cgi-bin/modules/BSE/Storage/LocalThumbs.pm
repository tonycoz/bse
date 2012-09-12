package BSE::Storage::LocalThumbs;
use strict;
use BSE::Storage::LocalBase;
our @ISA = qw(BSE::Storage::LocalBase);
use BSE::CfgInfo qw(cfg_scalecache_uri);

our $VERSION = "1.001";

sub _base_url {
  my ($self) = @_;

  return cfg_scalecache_uri($self->cfg);
}

sub store {
  my ($self, $path, $basename) = @_;
  # nothing to do

  return $self->_base_url . '/' . $basename;
}

sub url {
  my ($self, $basename) = @_;

  $self->_base_url . '/' . $basename;
}

1;
