#!perl -w
use strict;
use Test::More tests=>37;

my $gotmodule;
BEGIN { $gotmodule = use_ok('DevHelp::Date', ':all'); }

SKIP:
{
  skip "couldn't load module", 36 unless $gotmodule;
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
}
