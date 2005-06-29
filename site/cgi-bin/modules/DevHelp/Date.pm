package DevHelp::Date;
use strict;
require Exporter;
use vars qw(@EXPORT_OK %EXPORT_TAGS @ISA);
@ISA = qw(Exporter);
@EXPORT_OK = 
  qw(dh_parse_date dh_parse_date_sql dh_parse_time dh_parse_time_sql);
%EXPORT_TAGS =
  (
   all => \@EXPORT_OK,
   sql => [ grep /_sql$/, @EXPORT_OK ],
  );

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

sub dh_parse_time {
  my ($time, $rmsg) = @_;

  if ($time =~ /^\s*(\d+)[:. ]?(\d{2})\s*$/) {
    # 24 hour time
    my ($hour, $min) = ($1, $2);

    if ($hour > 23) {
      $$rmsg = "Hour must be from 0 to 23 for 24-hour time";
      return;
    }
    if ($min > 59) {
      $$rmsg = "Minutes must be from 0 to 59";
      return;
    }

    return (0+$hour, 0+$min, 0);
  }
  else {
    # try for 12 hour time
    my ($hour, $min, $ampm);

    if ($time =~ /^\s*(\d+)\s*(?:([ap])m?)\s*$/i) {
      # "12am", "2pm", etc
      ($hour, $min, $ampm) = ($1, 0, $2);
    }
    elsif ($time =~ /^\s*(\d+)[.: ](\d{2})\s*(?:([ap])m?)\s*$/i) {
      ($hour, $min, $ampm) = ($1, $2, $3);
    }
    else {
      $$rmsg = "Unknown time format";
      return;
    }
    if ($hour < 1 || $hour > 12) {
      $$rmsg = "Hour must be from 1 to 12 for 12 hour time";
      return;
    }
    if ($min > 59) {
      $$rmsg = "Minutes must be from 0 to 59";
      return;
    }
    $hour = 0 if $hour == 12;
    $hour += 12 if lc $ampm eq 'p';

    return (0+$hour, 0+$min, 0);
  }
}

sub dh_parse_time_sql {
  my ($time, $rmsg) = @_;

  my ($hour, $min, $sec) = dh_parse_time($time, $rmsg)
    or return;

  sprintf("%02d:%02d:%02d", $hour, $min, $sec);
}

1;
