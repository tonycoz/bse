package BSE::Storage::LocalThumbs;
use strict;
use BSE::Storage::LocalBase;
our @ISA = qw(BSE::Storage::LocalBase);

our $VERSION = "1.000";

sub _base_url {
  my ($self) = @_;

  return $self->cfg->entry('paths', 'scalecacheurl', '/images/scaled');
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
