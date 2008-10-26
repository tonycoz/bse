#!perl -w
use strict;
use Test::More tests => 9;

BEGIN { use_ok('DevHelp::Validate'); }

{
  my %simple_date =
    (
     date => 
     {
      rules => 'date'
     },
    );
  
  my $val = DevHelp::Validate::Hash->new(fields => \%simple_date);
  ok($val, "got validation object");
  {
    my %errors;
    ok($val->validate({ date => "30/12/67" }, \%errors), "valid date");
  }
  {
    my %errors;
    ok(!$val->validate({ date => "32/12/67" }, \%errors),
       "obviously invalid date");
  }
  {
    my %errors;
    ok(!$val->validate({ date => "31/9/67" }, \%errors),
       "not so obviously invalid date");
  }
  {
    my %errors;
    ok(!$val->validate({ date => "29/2/67" }, \%errors),
       "leap year check 29/2/67");
  }
  {
    my %errors;
    ok($val->validate({ date => "28/2/67" }, \%errors),
       "leap year check 28/2/67");
  }
  {
    my %errors;
    ok($val->validate({ date => "29/2/80" }, \%errors),
       "leap year check 29/2/80");
  }
  {
    my %errors;
    ok($val->validate({ date => "29/12/2000" }, \%errors),
       "leap year check 29/2/2000");
  }
}
