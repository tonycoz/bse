#!perl -w
use strict;
use Test::More tests=>2;

my $gotmodule = require_ok('DevHelp::HTML');

SKIP: {
  skip "couldn't load module", 9 unless $gotmodule;

  DevHelp::HTML->import('escape_xml');

  is(escape_xml("<&\xE9"), '&lt;&amp;&#233;', "don't escape like html");
}
