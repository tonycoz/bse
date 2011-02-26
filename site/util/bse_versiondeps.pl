#!perl -l
use strict;
use ExtUtils::Manifest qw(maniread);

my $mani_name = shift || "MANIFEST";

my $mani = maniread($mani_name);

for (sort { lc $a cmp lc $b } keys %$mani) {
  /(Version|Modules)\.pm$/ and next;
  /::/ and next;
  print;
}

-d ".git" and print ".git";
