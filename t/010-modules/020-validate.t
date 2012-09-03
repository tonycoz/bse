#!perl -w
use strict;
use Test::More tests => 16;

BEGIN { use_ok('DevHelp::Validate'); }

{
  my %built_ins =
    (
     oneline =>
     {
      rules => "dh_one_line"
     },
    );
  my $val = DevHelp::Validate::Hash->new(fields => \%built_ins);
  ok($val, "got built-ins validation object");
  {
    my %errors;
    ok($val->validate({ oneline => "abc" }, \%errors), "valid oneline");
    is_deeply(\%errors, {}, "no errors set");
  }
  {
    my %errors;
    ok(!$val->validate({ oneline => "\x0D" }, \%errors), "invalid oneline (CR)");
    ok($errors{oneline}, "message for oneline");
  }
  {
    my %errors;
    ok(!$val->validate({ oneline => "\x0A" }, \%errors), "invalid oneline (LF)");
    ok($errors{oneline}, "message for oneline");
  }
}

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
