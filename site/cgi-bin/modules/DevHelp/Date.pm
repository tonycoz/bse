package DevHelp::Date;
use strict;
require Exporter;
use vars qw(@EXPORT_OK %EXPORT_TAGS @ISA);
@ISA = qw(Exporter);
@EXPORT_OK = 
  qw(dh_parse_date dh_parse_date_sql dh_parse_time dh_parse_time_sql
     dh_parse_sql_date dh_parse_sql_datetime dh_strftime_sql_datetime
     dh_valid_date);
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

  if ($time =~ /^\s*(\d+)[:. ]?(\d{2})(?:[:.](\d{2}))?\s*$/) {
    # 24 hour time
    my ($hour, $min, $sec) = ($1, $2, $3);

    if ($hour > 23) {
      $$rmsg = "Hour must be from 0 to 23 for 24-hour time";
      return;
    }
    if ($min > 59) {
      $$rmsg = "Minutes must be from 0 to 59";
      return;
    }
    defined $sec or $sec = 0;
    if ($sec > 59) {
      $$rmsg = "Seconds must be from 0 to 59";
      return;
    }

    return (0+$hour, 0+$min, 0+$sec);
  }
  else {
    # try for 12 hour time
    my ($hour, $min, $sec, $ampm);

    if ($time =~ /^\s*(\d+)\s*(?:([ap])m?)\s*$/i) {
      # "12am", "2pm", etc
      ($hour, $min, $sec, $ampm) = ($1, 0, 0, $2);
    }
    elsif ($time =~ /^\s*(\d+)[.: ](\d{2})\s*(?:([ap])m?)\s*$/i) {
      ($hour, $min, $sec, $ampm) = ($1, $2, 0, $3);
    }
    elsif ($time =~ /^\s*(\d+)[.: ](\d{2})[:.](\d{2})\s*(?:([ap])m?)\s*$/i) {
      ($hour, $min, $sec, $ampm) = ($1, $2, $3, $4);
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
    if ($sec > 59) {
      $$rmsg = "Seconds must be from 0 to 59";
      return;
    }
    $hour = 0 if $hour == 12;
    $hour += 12 if lc $ampm eq 'p';

    return (0+$hour, 0+$min, 0+$sec);
  }
}

sub dh_parse_time_sql {
  my ($time, $rmsg) = @_;

  my ($hour, $min, $sec) = dh_parse_time($time, $rmsg)
    or return;

  sprintf("%02d:%02d:%02d", $hour, $min, $sec);
}

sub dh_parse_sql_date {
  my ($date) = @_;

  $date =~ /^(\d+)\D+(\d+)\D+(\d+)/
    or return;

  return (0+$1, 0+$2, 0+$3);
}

sub dh_parse_sql_datetime {
  my ($datetime) = @_;

  my ($year, $month, $day, $hour, $min, $sec) = 
    ($datetime =~ /^(\d+)\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)/)
      or return;

  return ($year, 0+$month, 0+$day, 0+$hour, 0+$min, 0+$sec);
}

sub dh_strftime_sql_datetime {
  my ($format, $datetime) = @_;

  my ($year, $month, $day, $hour, $min, $sec) = 
    dh_parse_sql_datetime($datetime)
      or return;

  $year -= 1900;
  --$month;

  require POSIX;
  return POSIX::strftime($format, $sec, $min, $hour, $day, $month, $year, 
			 0, 0);
}

=item dh_valid_date($year, $month, $day)

Validate the value ranges for a date.

Returns a true value on success.

=cut

sub dh_valid_date {
  my ($year, $month, $day) = @_;

  $month >= 1 and $month <= 12
    or return;

  $day >= 1
    or return;

  my $days_in_month;
  if ($month == 2) {
    my $leap = $year % 4 == 0 && $year % 100 != 0 || $year % 400 == 0;
    $days_in_month = $leap ? 29 : 28;
  }
  else {
    $days_in_month = [ 31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]->[$month-1];
  }
  $day <= $days_in_month
    or return;

  return 1;
}

1;
