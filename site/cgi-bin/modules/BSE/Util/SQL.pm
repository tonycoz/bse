package BSE::Util::SQL;
use strict;
use vars qw(@EXPORT_OK @ISA %EXPORT_TAGS);
require 'Exporter.pm';
@EXPORT_OK = qw/now_datetime sql_datetime date_to_sql sql_to_date sql_date 
                now_sqldate now_sqldatetime sql_datetime_to_epoch
                sql_normal_date sql_add_date_days sql_add_date_months/;
%EXPORT_TAGS = 
  (
   datemath => [ qw/sql_normal_date sql_add_date_days sql_add_date_months/ ],
   all => \@EXPORT_OK,
  );
@ISA = qw/Exporter/;

our $VERSION = "1.000";

use constant SECONDS_PER_DAY => 86400;

=head1 NAME

  BSE::Util::SQL - very basic tools for working with databases.

=head1 SYNOPSIS

  my $sqlnow = now_sqldatetime();
  my $sqlnowdate = now_sqldate();
  my $sqlthen = sql_datetime($when);
  my $sqldate = date_to_sql($date);
  my $date = sql_to_date($sqldate);
  my $epoch = sql_datetime_to_epoch($sqldate);

=head1 DESCRIPTION

Some basic tools for working with the database, including things like
formatting and extracting dates.

=over

=item sql_datetime($time_t)

=cut

sub sql_datetime {
  use POSIX qw/strftime/;
  return strftime('%Y-%m-%d %H:%M:%S', localtime shift);
}

# obsolete
sub now_datetime {
  return sql_datetime(time);
}

sub now_sqldatetime {
  return sql_datetime(time);
}

sub sql_date {
  use POSIX qw/strftime/;
  return strftime('%Y-%m-%d', localtime shift);
}

sub now_sqldate {
  return sql_date(time);
}

sub date_to_sql {
  my $date = shift;

  my ($day, $month, $year) = $date =~ /(\d+)\D+(\d+)\D+(\d+)/;

  return sprintf("%04d-%02d-%02d", $year, $month, $day);
}

sub sql_to_date {
  my $sqldate = shift;

  my ($year, $month, $day) = $sqldate =~ /^(\d+)\D+(\d+)\D+(\d+)/;

  return "$day/$month/$year";
}

sub sql_datetime_to_epoch {
  my $sqldate = shift;

  my ($year, $month, $day, $hour, $min, $sec) = 
    $sqldate =~ /^(\d+)\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)/;
  use POSIX qw(mktime);
  return mktime($sec, $min, $hour, $day, $month-1, $year-1900);
}

sub sql_normal_date {
  my ($sqldate) = @_;

  return unless $sqldate =~ /^(\d+)\D+(\d+)\D+(\d+)/;

  return sprintf("%04d-%02d-%02d", $1, $2, $3);
}

sub sql_add_date_days {
  my ($sqldate, $days) = @_;

  $sqldate = sql_normal_date($sqldate)
    or return;

  my $epoch = sql_datetime_to_epoch("$sqldate 12:00:00");
  $epoch += $days * SECONDS_PER_DAY;
  return strftime("%Y-%m-%d", localtime $epoch);
}

my @leap_days_per_month =
  qw(31 29 31
     30 31 30
     31 31 30
     31 30 31);

my @noleap_days_per_month =
  qw(31 28 31
     30 31 30
     31 31 30
     31 30 31);

sub sql_add_date_months {
  my ($sqldate, $months) = @_;

  my ($year, $month, $day) = $sqldate =~ /^(\d+)\D+(\d+)\D+(\d+)/
    or return;

  my $years = int($months / 12);
  $months -= 12 * $years;

  $year += $years;
  $month += $months;
  if ($month > 12) {
    ++$year;
    $month -= 12;
  }

  # make sure the dom is still within the month
  my $leap = $year % 4 == 0 && $year % 100 != 0;
  my $days_per_month = $leap ? \@leap_days_per_month : \@noleap_days_per_month;

  my $days_in_month = $days_per_month->[$month-1];
  $day > $days_in_month and $day = $days_in_month;

  return sprintf("%04d-%02d-%02d", $year, $month, $day);
}

1;
