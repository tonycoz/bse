#!perl -w
use strict;
use Test::More tests => 3;

use BSE::Countries qw(bse_country_code);

is(bse_country_code("Australia"), "AU", "we know where australia is");
is(bse_country_code("new zealand"), "NZ", "we know where new zealand is");
is(bse_country_code("not a country"), undef, "we know how to fail");
