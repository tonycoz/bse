package BSE::Util::SQL;
use strict;
use vars qw(@EXPORT_OK @ISA);
require 'Exporter.pm';
@EXPORT_OK = qw/now_datetime sql_datetime date_to_sql sql_to_date sql_date now_sqldate/;
@ISA = qw/Exporter/;

=head1 NAME

  BSE::Util::SQL - very basic tools for working with databases.

=head1 SYNOPSIS

  my $sqlnow = now_sqldatetime();
  my $sqlthen = sql_datetime($when);
  my $sqldate = date_to_sql($date);
  my $date = sql_to_date($sqldate);

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

sub now_datetime {
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

1;
