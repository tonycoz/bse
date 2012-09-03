#!perl -w
use strict;
use Test::More tests => 8;
use BSE::Cfg;
use Courier::ByUnitAU;

my $cfg = BSE::Cfg->new_from_text(text => <<EOS, path => ".");
[by unit au shipping]
description=testing
base=1000
perunit=100
EOS

my $c = Courier::ByUnitAU->new
  (
   config => $cfg,
  );

ok($c, "create courier object");
is($c->description, "testing", "test description");
is($c->name, "by-unit-au", "check name");
ok($c->can_deliver(country => "AU"), "can deliver to australia");
ok(!$c->can_deliver(country => "US"), "Can't deliver to US");
is($c->calculate_shipping
   (
    country => "AU",
    items =>
    [
     { units => 1 }
    ]
   ), 1000, "one unit order");
is($c->calculate_shipping
   (
    country => "AU",
    items =>
    [
     { units => 2 }
    ]
   ), 1100, "two unit order");
is($c->calculate_shipping
   (
    country => "AU",
    items =>
    [
     { units => 2 },
     { units => 1 },
     { units => 1 }
    ]
   ), 1300, "four unit order");
