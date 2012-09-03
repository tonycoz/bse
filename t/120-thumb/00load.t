#!perl -w
use strict;
use Test::More;

BEGIN {
  eval "use Imager; 1"
    or plan skip_all => "Imager not installed";
}

plan tests => 1;
use_ok("BSE::Thumb::Imager");
