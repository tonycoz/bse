#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.54:0.0'; }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use Constants;
use BSE::UserReg;
use BSE::Request;
use Carp 'confess';

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;
my $result = BSE::UserReg->dispatch($req);

# just for now, eventually all UserReg methods should properly return
# a result
if ($result) {
  my $cfg = $req->cfg;
  undef $req;
  BSE::Template->output_resultc($cfg, $result);
}
