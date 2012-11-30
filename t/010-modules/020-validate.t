#!perl -w
use strict;
use Test::More tests => 34;

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
  my %dates =
    (
     date => 
     {
      rules => 'date'
     },
    );
  
  my $val = DevHelp::Validate::Hash->new(fields => \%dates);
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
  my %rules =
    (
     monday =>
     {
      date => 1,
      dow => 1,
     },
     mondayb =>
     {
      date => 1,
      dow => "mon",
     },
     weekend =>
     {
      date => 1,
      dow => "sat,sun",
     },
     weekendmsg =>
     {
      date => 1,
      dow => "sat,sun",
      dowmsg => '$n must be on a weekend',
     },
     weekday =>
     {
      date => 1,
      dow => "1,2,3,4,5",
     },
    );
  { # dow as numbers
    my $val = DevHelp::Validate::Hash->new
      (
       fields =>
       {
	date => { rules => "monday" },
       },
       rules => \%rules,
      );
    {
      my %errors;
      ok($val->validate({ date => "2/1/2012" }, \%errors),
	 "check 2/1/2012 is a monday");
      is_deeply(\%errors, {}, "no errors");
    }
    {
      my %errors;
      ok(!$val->validate({ date => "3/1/2012" }, \%errors),
	 "check 3/1/2012 isn't a monday");
      is_deeply(\%errors, { date => "date must fall on a Monday" }, "check errors");
    }
  }
  { # dow as mon, tue etc
    my $val = DevHelp::Validate::Hash->new
      (
       fields =>
       {
	date => { rules => "mondayb" },
       },
       rules => \%rules,
      );
    {
      my %errors;
      ok($val->validate({ date => "2/1/2012" }, \%errors),
	 "check 2/1/2012 is a monday");
      is_deeply(\%errors, {}, "no errors");
    }
    {
      my %errors;
      ok(!$val->validate({ date => "3/1/2012" }, \%errors),
	 "check 3/1/2012 isn't a monday");
      is_deeply(\%errors, { date => "date must fall on a Monday" }, "check errors");
    }
  }
  { # weekend as tokens
    my $val = DevHelp::Validate::Hash->new
      (
       fields =>
       {
	date => { rules => "weekend" },
       },
       rules => \%rules,
      );
    {
      my %errors;
      ok($val->validate({ date => "7/1/2012" }, \%errors),
	 "check 7/1/2012 is on the weekend");
      is_deeply(\%errors, {}, "no errors");
    }
    {
      my %errors;
      ok(!$val->validate({ date => "3/1/2012" }, \%errors),
	 "check 3/1/2012 isn't on the weekend");
      is_deeply(\%errors, { date => "date must fall on any of Saturday, Sunday" }, "check errors");
    }
  }

  { # weekend as tokens, custom message
    my $val = DevHelp::Validate::Hash->new
      (
       fields =>
       {
	date => { rules => "weekendmsg" },
       },
       rules => \%rules,
      );
    {
      my %errors;
      ok(!$val->validate({ date => "3/1/2012" }, \%errors),
	 "check 3/1/2012 isn't on the weekend");
      is_deeply(\%errors, { date => "date must be on a weekend" }, "check errors");
    }
  }

  { # weekday as tokens
    my $val = DevHelp::Validate::Hash->new
      (
       fields =>
       {
	date => { rules => "weekday" },
       },
       rules => \%rules,
      );
    {
      my %errors;
      ok($val->validate({ date => "3/1/2012" }, \%errors),
	 "check 7/1/2012 is on a weekday");
      is_deeply(\%errors, {}, "no errors");
    }
    {
      my %errors;
      ok(!$val->validate({ date => "1/1/2012" }, \%errors),
	 "check 3/1/2012 isn't on a weekday");
      is_deeply(\%errors, { date => "date must fall on any of Monday, Tuesday, Wednesday, Thursday, Friday" }, "check errors");
    }
  }
}
