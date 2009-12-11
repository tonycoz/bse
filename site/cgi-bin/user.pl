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
BSE::UserReg->dispatch($req);
