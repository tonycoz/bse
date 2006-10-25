#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use BSE::Request;
use BSE::Template;
use Carp 'confess';
use BSE::UI::AdminReport;

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;

my $result = BSE::UI::AdminReport->dispatch($req);
$req->output_result($result);
