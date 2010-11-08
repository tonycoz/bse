package BSE::Storage::LocalImages;
use strict;
use BSE::Storage::LocalBase;
our @ISA = qw(BSE::Storage::LocalBase);

our $VERSION = "1.000";

sub store {
  my ($self, $path, $basename) = @_;
  # nothing to do

  return '/images/' . $basename;
}

sub url {
  my ($self, $basename) = @_;
  '/images/' . $basename;
}

1;
