package BSE::Util::Valid;
use strict;
use vars qw(@EXPORT_OK @ISA);
require 'Exporter.pm';
@EXPORT_OK = qw/valid_date/;
@ISA = qw/Exporter/;

sub valid_date {
  $_[0] =~ m!^\d+[/-]\d+[/-]\d+$!;
}

1;

