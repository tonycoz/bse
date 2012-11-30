#!perl -w
use strict;
use Test::More tests=>51;

my $gotmodule;
BEGIN { $gotmodule = use_ok('DevHelp::Date', ':all'); }

SKIP:
{
  skip "couldn't load module", 41 unless $gotmodule;
  my $msg;
  is_deeply([ dh_parse_time("10:00", \$msg) ], [ 10, 0, 0 ], "parse 10:00");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("10pm", \$msg) ], [ 22, 0, 0 ], "parse 10pm");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("10 05", \$msg) ], [ 10, 5, 0 ], "parse 10 05");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("12am", \$msg) ], [ 0, 0, 0 ], "parse 12am");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("12pm", \$msg) ], [ 12, 0, 0 ], "parse 12pm");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("12.01pm", \$msg) ], [ 12, 1, 0 ], "parse 12.01pm");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("1pm", \$msg) ], [ 13, 0, 0 ], "parse 1pm");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("1.00PM", \$msg) ], [ 13, 0, 0 ], "parse 1.00PM");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("12:59PM", \$msg) ], [ 12, 59, 0 ], 
	    "parse 12:59PM");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("0000", \$msg) ], [ 0, 0, 0 ], "parse 0000");
  is($msg, undef, "no error");
  undef $msg;
  is_deeply([ dh_parse_time("1101", \$msg) ], [ 11, 1, 0 ], "parse 1101");
  is($msg, undef, "no error");

  is_deeply([ dh_parse_time("11:01:02", \$msg) ], [ 11, 1, 2 ],
	    "parse 11:01:02") or diag $msg;
  is_deeply([ dh_parse_time("11:01:02pm", \$msg) ], [23, 1, 2 ],
	    "parse 11:01:02pm") or diag $msg;

  # fail a bit
  undef $msg;
  is_deeply([ dh_parse_time("xxx", \$msg) ], [], "parse xxx");
  is($msg, "Unknown time format", "got an error");
  undef $msg;
  is_deeply([ dh_parse_time("0pm", \$msg) ], [], "parse 0pm");
  is($msg, "Hour must be from 1 to 12 for 12 hour time", "got an error");
  undef $msg;
  is_deeply([ dh_parse_time("13pm", \$msg) ], [], "parse 13pm");
  is($msg, "Hour must be from 1 to 12 for 12 hour time", "got an error");
  undef $msg;
  is_deeply([ dh_parse_time("12:60am", \$msg) ], [], "parse 12:60am");
  is($msg, "Minutes must be from 0 to 59", "got an error");
  undef $msg;
  is_deeply([ dh_parse_time("2400", \$msg) ], [], "parse 2400");
  is($msg, "Hour must be from 0 to 23 for 24-hour time", "got an error");
  undef $msg;
  is_deeply([ dh_parse_time("1360", \$msg) ], [], "parse 1360");
  is($msg, "Minutes must be from 0 to 59", "got an error");

  # sql times
  
  undef $msg;
  is(dh_parse_time_sql("2:30pm"), "14:30:00", "2:30pm to sql");
  is($msg, undef, "no error");

  # parse SQL date
  is_deeply([ dh_parse_sql_date("2005-07-12") ], [ 2005, 7, 12 ],
	    "simple sql date parse");
  is_deeply([ dh_parse_sql_date("20") ], [ ],
	    "invalid sql date parse");
  is_deeply([ dh_parse_sql_datetime("2005-06-30 12:00:05") ],
	    [ 2005, 6, 30, 12, 0, 5 ], "parse SQL date time");
  is_deeply([ dh_parse_sql_datetime("2005-06-30 12") ],
	    [ ], "invalid parse SQL date time");
  is(dh_strftime_sql_datetime("%d/%m/%Y", "2005-06-30 12:00:05"),
     "30/06/2005", "dh_strftime_sql_datetime");

  is(dh_strftime_sql_datetime("%a %U %j %d/%m/%Y", "2005-06-30 12:00:05"),
     "Thu 26 181 30/06/2005", "dh_strftime_sql_datetime dow check");

  is(dh_strftime("%a %U %j %F %T", 20, 5, 12, 30, 5, 105),
     "Thu 26 181 2005-06-30 12:05:20",
     "dh_strftime");

  # day of week
  is(dh_date_dow(2012, 11, 29), 4, "29/11/2012 is a thursday");
  is(dh_date_dow(2012, 11,  3), 6, "3/11/2012 is a saturday");
  is(dh_date_dow(2012, 11, 11), 0, "11/11/2012 is a sunday");
  is(dh_date_dow(2012,  6, 1),  5, "1/6/2012 is a friday");
  is(dh_date_dow(2008,  2, 29), 5, "29/2/2008 is a friday");
}
