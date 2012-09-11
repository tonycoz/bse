#!perl -w
use strict;
use BSE::Test qw();
use File::Spec;
use Test::More tests => 3;

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

use BSE::API qw(:all);

my $base_cgi = File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin");
ok(bse_init($base_cgi),   "initialize api")
  or print "# failed to bse_init in $base_cgi\n";

require BSE::TB::AdminGroups;
my $name = "060-admin-group test " . time;
my $group = BSE::TB::AdminGroups->make
   (
    name => $name,
   );

ok($group, "make a group with only a name");

ok($group->remove, "remove the group");
undef $group;

END {
  $group->remove if $group;
}
