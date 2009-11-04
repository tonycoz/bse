#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_cfg);
use BSE::NotifyFiles;

chdir "$FindBin::Bin/../cgi-bin"
  or warn "Could not change to cgi-bin directory: $!\n";
Getopt::Long::Configure('bundling');
my $verbose;
GetOptions("v:i", \$verbose);
defined $verbose && !$verbose
  and $verbose = 1;

my $cfg = bse_cfg;

my $notifier = BSE::NotifyFiles->new
  (
   verbose => $verbose,
   output => sub { print "@_\n" },
   error => sub { print STDERR "@_\n" },
   cfg => $cfg,
  );

$notifier->run;

