package BSE::Storage::LocalFiles;
use strict;
use BSE::Storage::LocalBase;
our @ISA = qw(BSE::Storage::LocalBase);

sub store {
  my ($self, $path, $basename) = @_;
  # nothing to do

  return '';
}

sub url {
  my ($self, $basename, $object) = @_;

  return '';
}

1;
