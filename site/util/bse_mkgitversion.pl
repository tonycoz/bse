#!perl -w
use strict;

my $release = shift;

my $output = shift
  or die "Usage: $0 <bserev> <outfile>\n";

$release =~ /^\d+\.\d+(_\d+)?$/
  or die "Invalid revision";

if (-d ".git") {
  my ($git_desc) = `git describe`;
  chomp $git_desc;

  my @status = `git status -s`;
  if (@status) {
    $git_desc .= " +" . scalar(@status) . " local modifications";
  }

  $release .= " GIT $git_desc";
}

open VERSION, "> $output"
  or die "Cannot create $output: $!\n";
print VERSION <<EOS;
package BSE::Version;
use strict;

my \$RELEASE = "$release";

sub version { \$RELEASE }

1;
EOS

close VERSION;
