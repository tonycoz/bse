#!perl -w
use strict;
use Test::More tests=>11;

use BSE::Util::SQL qw(:all);

is(sql_normal_date("2004/02/10"), "2004-02-10", "separators");
is(sql_normal_date("2004-02-10 10:00:00"), "2004-02-10", "strip time");

# sql_add_date_months():
is(sql_add_date_months("2004-02-10", 2), "2004-04-10", 
   "add months, simple");
is(sql_add_date_months("2004-02-10", 12), "2005-02-10",
   "add months, one year");
is(sql_add_date_months("2004-02-10", 11), "2005-01-10",
   "add months, 11 months");
is(sql_add_date_months("2004-02-10", 13), "2005-03-10",
   "add months, 13 months");
is(sql_add_date_months("2004-01-30", 1), "2004-02-29",
   "add months, to a shorter month");
is(sql_add_date_months("2004-01-30", 13), "2005-02-28",
   "add months, to a shorter month in non-leap year");


# sql_add_date_days():
is(sql_add_date_days("2004-02-10", 2), "2004-02-12",
   "add days, simple");
is(sql_add_date_days("2004-02-29", 1), "2004-03-01",
   "add days, span month");
is(sql_add_date_days("2004-12-31", 1), "2005-01-01",
   "add days, span year");

