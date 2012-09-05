#!perl -w
# BSE::Cfg tests
use strict;
use Test::More;

BEGIN {
  eval "use BSE::Cfg; 1"
    or plan skip_all => "Cannot load BSE::Cfg";
}

plan tests => 15;

#ok(chdir "t/cfg", "chdir to cfg dir");
my $cfg = eval { BSE::Cfg->new(path => "t/cfg") };
ok($cfg, "made a config");
is($cfg->entry("alpha", "beta"), "one", "check simple lookup");
is($cfg->entryVar("var", "varb"), "ab", "simple variable lookup");
is($cfg->entryVar("var", "varc"), "tt", "complex variable lookup");

is($cfg->entry("isafile", "key"), "value", "value from include");

# values from directory includes, conflict resolution
is($cfg->entry("conflict", "keya"), "valuez", "conflict resolution");

# utf8
is($cfg->entry("utf8", "omega"), "\x{2126}", "check utf8 parsed");
is($cfg->entry("utf8", "omega2"), "\x{2126}", "check utf8 parsed from include");

# missing values
is($cfg->entry("unknown", "keya"), undef, "missing value no default");
is($cfg->entry("unknown", "keya", "abc"), "abc", "missing value with default");

# include included by variable name
is($cfg->entry("varinc", "vara"), "somevalue", "include included by variable name");

# get entire sections
is_deeply({ $cfg->entriesCS("conflict") },
	  { keya => "valuez" }, "CS section with a value");
is_deeply([ $cfg->orderCS("conflict") ],
	  [ qw/keya keya/ ], "original case keys in order of appearance");

{
  my $cfg = BSE::Cfg->new_from_text(text => <<EOS, path => ".");
[by unit au shipping]
description=testing
base=1000
unit=100
EOS
  ok($cfg, "make cfg from text");
  is($cfg->entry("by unit au shipping", "description"), "testing",
     "test we got the cfg");
}
