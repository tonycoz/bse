package BSE::Util::Valid;
use strict;
use vars qw(@EXPORT_OK @ISA);
require 'Exporter.pm';
@EXPORT_OK = qw/valid_date convert_date_to_sql/;
@ISA = qw/Exporter/;

our $VERSION = "1.000";

sub valid_date {
  $_[0] =~ m!^\d+[/-]\d+[/-]\d+$!;
}

sub convert_date_to_sql {
  my ($date) = @_;
  my ($day, $month, $year) = $date =~  m!^\s*(\d+)[/-](\d+)[/-](\d+)$!
    or return;

  if ($year < 100) {
    $year += $year < 50 ? 2000 : 1900;
  }

  print STDERR "date: $year-$month-$day\n";
  return "$year-$month-$day";
}

1;

