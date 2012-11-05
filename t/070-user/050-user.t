#!perl -w
use strict;
use BSE::Test qw(make_ua base_url test_actions);
use Test::More tests => 2;
use Carp "confess";
use File::Spec;

$SIG{__DIE__} = sub { confess @_ };

BEGIN {
  unshift @INC, File::Spec->catdir(BSE::Test::base_dir(), "cgi-bin", "modules");
}

require_ok("BSE::UserReg");

test_actions("BSE::UserReg");