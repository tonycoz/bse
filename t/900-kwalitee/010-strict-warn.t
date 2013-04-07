#!perl -w
use strict;
use File::Find;
use Test::More;

my @files;
open MANIFEST, "< MANIFEST" or die "Cannot open MANIFEST";
while (<MANIFEST>) {
  chomp;
  next if /^\s*\#/;
  s/\s+.*//;
  push @files, $_ if /\.(pm|t|pl)$/;
}
close MANIFEST;
my @scripts = grep /\.(pl|t)$/, @files;
plan tests => scalar(@files) + scalar(@scripts);
for my $file (@files) {
  open SRC, "< $file" or die "Cannot open $file: $!";
  my $data = do { local $/; <SRC> };
  close SRC;
  ok($data =~ /^use\s+strict/m, "use strict in $file");
  if ($file =~ /\.(pl|t)$/) {
    ok($data =~ /#!.*perl.*-w|use warnings;/m, "-w or use warnings in $file");
  }
}
