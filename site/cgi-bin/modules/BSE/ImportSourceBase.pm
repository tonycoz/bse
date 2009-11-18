package BSE::ImportSourceBase;
use strict;
use Config;

sub new {
  my ($class, %opts) = @_;

  my $importer = delete $opts{importer};
  my $opts = delete $opts{opts};

  return bless
    {
    }, $class;
}

1;
