#!perl -w
use strict;
use Getopt::Long;
use FindBin;

Getopt::Long::Configure('bundling');
my $verbose;
my $actions;
my $nothing;
my $bse_dir = "../cgi-bin";
my $help;
GetOptions
  (
   "v:i", \$verbose,
   "a|actions" => \$actions,
   "b|bse=s" => \$bse_dir,
   "n|nothing" => \$nothing,
   "h" => \$help,
  );

if ($help) {
  print <<EOS;
Usage: perl $0 [options]
Upgrade various bits of BSE.

Currently:

 - hashes unhashed site user passwords
 - hashes unhashed admin user passwords

Options:
 -n - only display the actions to perform, but make no changes
      (displays items as "skipped")
 -a - display the actions as their done
 -b cgidir - locate the BSE CGI directory (default ../cgi-bin)
 -v - display progress
 -v=2 - more details
 -h - display this help text
EOS
  exit 0;
}

defined $verbose && !$verbose
  and $verbose = 1;

my %opts =
  (
   verbose => $verbose,
   actions => $actions,
   nothing => $nothing,
   progress => sub { print @_, "\n" },
  );

unshift @INC, "$bse_dir/modules";

-d "$bse_dir/modules"
  or die "$0: $bse_dir isn't a BSE cgi-bin\n";

require BSE::API;

BSE::API::bse_init($bse_dir);

require BSE::Upgrade::Passwords;
BSE::Upgrade::Passwords->upgrade(%opts);
