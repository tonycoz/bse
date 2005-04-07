package DevHelp::Date;
use strict;
require Exporter;
use vars qw(@EXPORT_OK @ISA);
@EXPORT_OK = qw(dh_parse_date dh_parse_date_sql);
@ISA = qw(Exporter);

use constant SECS_PER_DAY => 24 * 60 * 60;

# for now just a simple date parser
sub dh_parse_date {
  my ($when, $rmsg, $bias) = @_;

  $bias ||= 0;

  my ($year, $month, $day);
  if (($day, $month, $year) = $when =~ /(\d+)\D+(\d+)\D+(\d+)/) {
    if ($year < 100) {
      my $base_year = 1900 + (localtime)[5];
      if ($bias < 0) {
	$base_year = $base_year - 50;
      }
      elsif ($bias > 0) {
	$base_year = $base_year + 50;
      }
      my $cent = int($base_year / 100) * 100;
      my $work_year = $cent + $year;
      if ($work_year > $base_year + 50) {
	$work_year -= 100;
      }
      elsif ($work_year < $base_year - 50) {
	$work_year += 100;
      }
      
      $year = $work_year;
    }
  }
  elsif ($when =~ /^\s*([+-]\d+)y\s*$/) {
    my $yoffset = $1;
    ($year, $month, $day) = (localtime)[5,4,3];
    ++$month;
    $year = $year + 1900 + $yoffset;
  }
  elsif ($when =~ /^\s*([+-]\d+)d\s*$/) {
    my $doffset = $1;
    ($year, $month, $day) = (localtime(time()+$doffset*SECS_PER_DAY))[5,4,3];
    ++$month;
    $year += 1900;
  }
  else {
    $$rmsg = "Invalid date format";
    return;
  }


  return ($year, $month, $day);
}

sub dh_parse_date_sql {
  my ($when, $rmsg, $bias) = @_;

  my ($year, $month, $day) = dh_parse_date($when, $rmsg, $bias)
    or return;

  return sprintf("%04d-%02d-%02d", $year, $month, $day);
}

1;
