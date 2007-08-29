#!perl -w
use strict;

my $release = shift;

my $output = shift
  or die "Usage: $0 <bserev> <outfile>\n";

$release =~ /^\d+\.\d+(_\d+)?$/
  or die "Invalid revision";

my ($svn_rev_line) = grep /^Revision/, `svn info`;
$svn_rev_line =~ /(\d+)/
  or die "Invalid svn revision";
my $svn_rev = $1;

open VERSION, "> $output"
  or die "Cannot create $output: $!\n";
print VERSION <<EOS;
package BSE::Version;
use strict;

my \$VERSION = "$release SVN r$svn_rev";

sub version { \$VERSION }

1;
EOS

close VERSION;
