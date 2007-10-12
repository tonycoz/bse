#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.245:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use CGI ':standard';
use BSE::Request;
use BSE::UI::Thumb;
use BSE::Template;
use Carp 'confess';

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;
my $result = BSE::UI::Thumb->dispatch($req);
BSE::Template->output_result($req, $result);
