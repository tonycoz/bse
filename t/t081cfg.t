#!perl -w
# BSE::Cfg tests
use strict;
use Test::More;

BEGIN {
  eval "use BSE::Cfg; 1"
    or plan skip_all => "Cannot load BSE::Cfg";
}

plan tests => 9;

#ok(chdir "t/cfg", "chdir to cfg dir");
my $cfg = eval { BSE::Cfg->new(path => "t/cfg") };
ok($cfg, "made a config");
is($cfg->entry("alpha", "beta"), "one", "check simple lookup");
is($cfg->entryVar("var", "varb"), "ab", "simple variable lookup");
is($cfg->entryVar("var", "varc"), "tt", "complex variable lookup");

is($cfg->entry("isafile", "key"), "value", "value from include");

# values from directory includes, conflict resolution
is($cfg->entry("conflict", "keya"), "valuez", "conflict resolution");

# missing values
is($cfg->entry("unknown", "keya"), undef, "missing value no default");
is($cfg->entry("unknown", "keya", "abc"), "abc", "missing value with default");

# include included by variable name
is($cfg->entry("varinc", "vara"), "somevalue", "include included by variable name");
