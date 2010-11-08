package BSE::ImageHandler::Base;
use strict;
use Carp qw(confess);

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg option";

  return bless
    {
     cfg => $cfg,
    }, $class;
}

sub cfg {
  $_[0]{cfg};
}

sub thumb {
  my ($self, %opts) = @_;

  return "* thumb not implemented for " . (ref $self || $self) . " *";
}

1;
