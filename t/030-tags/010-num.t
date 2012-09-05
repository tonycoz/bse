#!perl -w
use strict;
use Test::More tests => 10;
use BSE::Cfg;
use Squirrel::Template;

use_ok("BSE::Util::Tags");

my $cfg = BSE::Cfg->new(path => "t/tags/");

my %acts =
  (
   BSE::Util::Tags->static(undef, $cfg),
   pi => "3.14159265",
   large => 1234567890,
  );

my @tests =
  ( # comment, template, output
   [ "num default", "<:number default [pi]:>", "3.14159265" ],
   [ "num places", "<:number places [pi]:>", "3" ],
   [ "num default large", "<:number default [large]:>", "1,234,567,890" ],
   [ "num new comma", "<:number space [large]:>", "1 234 567 890" ],
   [ "num comma limit", "<:number 9999 9999:>", "9999" ],
   [ "num comma limit2", "<:number 9999 10000:>", "10,000" ],
   [ "num cents", "<:number cents [large]:>", "12,345,678.90" ],
   [ "num cents", "<:number cents 999999:>", "9,999.99" ],
   [ "num decimal", "<:number decimal [large]:>", "12 345 678,90" ],
  );

for my $test (@tests) {
  my ($comment, $in, $out) = @$test;
  template_test($comment, $in, $out, \%acts);
}

sub template_test {
  my ($note, $in, $out, $acts) = @_;

  my $templater = Squirrel::Template->new;
  my $result = $templater->replace_template($in, $acts);
  return is($result, $out, $note);
}
