#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.51:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use BSE::DB;
use BSE::Request;
use BSE::Template;
use Carp 'confess';
use BSE::UI::NUser;

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;

my $result = BSE::UI::NUser->dispatch($req);

BSE::Template->output_result($req, $result);

