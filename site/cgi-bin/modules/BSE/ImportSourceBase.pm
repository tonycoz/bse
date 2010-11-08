package BSE::ImportSourceBase;
use strict;
use Config;

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  my $importer = delete $opts{importer};
  my $opts = delete $opts{opts};

  return bless
    {
    }, $class;
}

1;
