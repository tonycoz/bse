#!perl -w
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::Bin/../cgi-bin/modules";
use BSE::API qw(bse_init bse_cfg);
use Squirrel::Template;

bse_init("../cgi-bin");

Getopt::Long::Configure('bundling');
my $verbose;
my @includes;
my $utf8 = 1;
my $charset = "utf-8";
GetOptions("v", \$verbose,
	   "I|include=s" =>\@includes,
	   "utf8" => \$utf8,
	   "c|charset" => \$charset
	  );
$verbose = defined $verbose;

my $cfg = bse_cfg();

my $templater = Squirrel::Template->new
  (
   utf8 => $utf8,
   charset => $charset,
   template_dir => \@includes,
  );

my $file = shift
  or usage("No filename supplied");
my $p = $templater->parse_file($file);
print $_->[3], ":", $_->[2], ": ", $_->[4], "\n" for $templater->errors;

