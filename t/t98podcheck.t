#!perl -w
use strict;
use Test::More;
use ExtUtils::Manifest qw(maniread);
eval "use Test::Pod 1.00;";
plan skip_all => "Test::Pod 1.00 required for testing POD" if $@;
my $manifest = maniread();
my @pod = sort grep /\.(pm|pl|pod|PL)$/, keys %$manifest;
plan tests => scalar(@pod);
for my $file (@pod) {
  local $TODO = "working on fixing these";
  pod_file_ok($file, "pod ok in $file");
}
