#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.54:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use CGI ':standard';
use BSE::Request;
use BSE::UI::API;
use BSE::Template;
use Carp 'confess';

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new(nodatabase => 1, nosession => 1);
my $result = BSE::UI::API->dispatch($req);
$req->output_result($result);
