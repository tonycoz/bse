#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_init bse_cfg);
use BSE::NotifyFiles;

Getopt::Long::Configure('bundling');
my $verbose;
GetOptions("v:i", \$verbose);
defined $verbose && !$verbose
  and $verbose = 1;

bse_init("$FindBin::Bin/../cgi-bin");

my $cfg = bse_cfg;

my $notifier = BSE::NotifyFiles->new
  (
   verbose => $verbose,
   output => sub { print "@_\n" },
   error => sub { print STDERR "@_\n" },
   cfg => $cfg,
  );

$notifier->run;

