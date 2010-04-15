#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use BSE::Request;
use BSE::Template;
use BSE::UI::FileProgress;

my $req = BSE::Request->new(nosession => 1, nodatabase => 1);

my $result = BSE::UI::FileProgress->dispatch($req);

$req->output_result($result);
