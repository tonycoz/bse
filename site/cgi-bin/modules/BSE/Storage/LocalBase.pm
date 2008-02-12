package BSE::Storage::LocalBase;
use strict;
use BSE::Storage::Base;
our @ISA = qw(BSE::Storage::Base);

sub unstore {
  my ($self, $basename) = @_;
  # nothing to do
}

sub sync {
  # does nothing
}

sub description {
  return 'Local';
}

1;
