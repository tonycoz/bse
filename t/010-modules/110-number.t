#!perl
use strict;
use BSE::Util::Format qw(bse_number);
use BSE::Cfg;
use Test::More;

{
  my $cfg = BSE::Cfg->new_from_text(text => <<CFG);
[number money]
comma=,
divisor=100
places=2
CFG
  is(BSE::Util::Format::bse_number("money", 1_000_000, $cfg), "10,000.00",
     "smoke test the basics");
}

{
  my $cfg = BSE::Cfg->new_from_text(text => <<CFG);
[number emptycomma]
comma=""
CFG
  is(BSE::Util::Format::bse_number("emptycomma", 10000000, $cfg), "10000000",
     "check empty comma doesn't infinite loop");
}

done_testing();
