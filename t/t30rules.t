#!perl -w
use strict;
use BSE::Test qw(ok);
use File::Find;

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
print "1..",scalar(@files) + scalar(@scripts),"\n";
for my $file (@files) {
  open SRC, "< $file" or die "Cannot open $file: $!";
  my $data = do { local $/; <SRC> };
  close SRC;
  ok($data =~ /^use\s+strict/m, "use strict in $file");
  if ($file =~ /\.(pl|t)$/) {
    ok($data =~ /#!.*perl.*-w/, "-w in $file");
  }
}
